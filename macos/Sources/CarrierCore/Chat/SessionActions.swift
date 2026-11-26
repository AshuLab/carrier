import Foundation
import Observation
import Synchronization

public enum SessionRemovalKind: Sendable {
    case archive
    case delete
    case clear
}

/// Archives, restores and deletes sessions through the host. Each call returns what the host refused, in words, nil when it worked;
/// `changed` is told after a success so the lists are read again.
@Observable public final class SessionActions {
    @ObservationIgnored private let host: ChatHost
    @ObservationIgnored private let log: (String) -> Void
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored public var changed: () -> Void = {}
    /// Said when `archiving` changes, for the lists to be drawn again.
    @ObservationIgnored public var archivingChanged: () -> Void = {}
    /// The sessions the person archived and that the host's list does not show archived yet: the lists draw them as archived at once, so the
    /// row goes when it is asked and not when the host has ended its agent and the next read arrives.
    @ObservationIgnored private let leaving = Mutex<Set<String>>([])
    public var archiving: Set<String> { leaving.withLock { $0 } }
    /// Whether the host's hello lists `regenerateTitle`, as `learnHost` last read it; the menu is built at once and cannot wait for the hello.
    @ObservationIgnored private let titlesRegenerable = Mutex(false)
    public var canRegenerateTitle: Bool { titlesRegenerable.withLock { $0 } }
    @ObservationIgnored public var confirmSessionRemoval: @MainActor (SessionRemovalKind, [String]) async -> Bool = { _, _ in true }
    @ObservationIgnored public var didRemoveSession: @MainActor (String) -> Void = { _ in }
    /// Only after a delete the host accepted: `didRemoveSession` also runs on archive, and an archived session can be restored.
    @ObservationIgnored public var didDeleteSession: @MainActor (String) -> Void = { _ in }

    /// What the app calls at start: a deleted session takes with it what `memory` kept for it.
    public func forgetDeletedSessions(in memory: OptionsMemory) { didDeleteSession = { memory.forget($0) } }

    public init(
        host: ChatHost, preferences: AppPreferences = AppPreferences(),
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) }
    ) {
        self.host = host
        self.preferences = preferences
        self.log = log
    }

    public func archive(_ id: String) async -> String? {
        guard await confirmSessionRemoval(.archive, [id]) else { return nil }
        leaving.withLock { _ = $0.insert(id) }
        archivingChanged()
        let refusal = await run("archive", id) { try await $0.archive(id, true) }
        if refusal == nil {
            await didRemoveSession(id)
        } else {
            // the host did not archive it: the row comes back, and the words tell why
            leaving.withLock { _ = $0.remove(id) }
            archivingChanged()
        }
        return refusal
    }

    public func restore(_ id: String) async -> String? {
        leaving.withLock { _ = $0.remove(id) }
        return await run("restore", id) { try await $0.archive(id, false) }
    }

    /// Forgets the sessions the host's list has caught up with: the ones it lists archived, and the ones it no longer lists.
    public func settle(_ rows: [SessionRow]) {
        leaving.withLock { ids in ids = ids.filter { id in rows.first { $0.id == id }.map { $0.archived == false } ?? false } }
    }

    public func delete(_ id: String) async -> String? {
        guard await confirmSessionRemoval(.delete, [id]) else { return nil }
        return await deleteConfirmedSession(id)
    }

    /// Ends the turn that is in progress.
    public func stop(_ id: String) async -> String? { await run("stop", id) { try await $0.interrupt(id) } }

    /// Sends the session to sleep: its agent closes and a message wakes it.
    public func sleep(_ id: String) async -> String? { await run("send to sleep", id) { try await $0.close(id) } }

    public func rename(_ id: String, _ title: String) async -> String? { await run("rename", id) { try await $0.rename(id, title) } }

    /// Reads what the host can do (its hello is kept by the link, so this is cheap) for the menus drawn after it.
    public func learnHost() async {
        let listed = (try? await host.capabilities())?.contains(.regenerateTitle) ?? false
        titlesRegenerable.withLock { $0 = listed }
    }

    public func regenerateTitle(_ id: String) async -> String? { await run("regenerate the title", id) { _ = try await $0.regenerateTitle(id) } }

    /// Writes the session's title again and answers the new one, or what the host refused in words.
    public func regeneratedTitle(_ id: String) async -> (title: String?, refusal: String?) {
        switch await attempt("regenerate the title", id, { try await $0.regenerateTitle(id) }) {
        case .success(let title): (title, nil)
        case .failure(let refusal): (nil, refusal.words)
        }
    }

    /// What an alert before a delete is: the question to ask, or what the host refused when it was asked what the deletion would discard.
    public enum Confirmation: Equatable {
        case ask(Question)
        /// The person switched the question off: delete without asking.
        case proceed
        case refused(String)
    }

    /// Asks the host what deleting the session would discard and builds its question; the deletion must not go ahead without it,
    /// unless the person switched the question off.
    public func confirmDelete(_ row: SessionRow) async -> Confirmation {
        guard preferences.confirmDelete else { return .proceed }
        switch await preview("delete \(row.id)", [row.id]) {
        case .success(let previews): return .ask(deleteSessionQuestion(row, worktree: previews.first { $0.sessionId == row.id }?.worktree))
        case .failure(let refusal): return .refused(refusal.words)
        }
    }

    /// The same for Clear sessions: one request for all of them, so a commit two worktrees share counts once.
    public func confirmClear(_ ids: [String]) async -> Confirmation {
        switch await preview("clear \(ids.count) sessions", ids) {
        case .success(let previews): .ask(clearSessionsQuestion(count: ids.count, previews: previews))
        case .failure(let refusal): .refused(refusal.words)
        }
    }

    /// Deletes each session; one the host refuses does not stop the rest, and a host that stops answering does.
    public func clear(_ ids: [String], bundle: Bundle? = nil, locale: Locale = .current) async -> String? {
        guard ids.isEmpty == false, await confirmSessionRemoval(.clear, ids) else { return nil }
        var deleted = 0
        var refusal: String?
        let summary = { (message: String) in Copy.archiveClearPartial(total: ids.count, deleted: deleted, message: message, bundle: bundle, locale: locale) }
        for id in ids {
            if let failed = await deleteConfirmedSession(id) {
                if refusal == nil { refusal = failed }
                if failed == ConversationModel.words(ControlError.closed) {
                    return refusal.map(summary)
                }
            } else {
                deleted += 1
            }
        }
        return refusal.map(summary)
    }

    private func deleteConfirmedSession(_ id: String) async -> String? {
        if let failed = await run("delete", id, { try await $0.delete(id) }) {
            return failed
        }
        await didRemoveSession(id)
        await didDeleteSession(id)
        return nil
    }

    private struct Refusal: Error { let words: String }

    private func preview(_ doing: String, _ ids: [String]) async -> Result<[SessionDeletePreview], Refusal> {
        do {
            return .success(try await host.deletePreview(ids))
        } catch {
            let words = ConversationModel.words(error)
            if case ControlError.remote = error {} else { log("could not ask what \(doing) would discard: \(words)") }
            return .failure(Refusal(words: words))
        }
    }

    private func run(_ doing: String, _ id: String, _ call: (ChatHost) async throws -> Void) async -> String? {
        if case .failure(let refusal) = await attempt(doing, id, { try await call($0) }) { return refusal.words }
        return nil
    }

    /// `run` that keeps what the call answers.
    private func attempt<Answer>(_ doing: String, _ id: String, _ call: (ChatHost) async throws -> Answer) async -> Result<Answer, Refusal> {
        do {
            let answer = try await call(host)
            changed()
            return .success(answer)
        } catch {
            let words = ConversationModel.words(error)
            // a refusal is the host answering as it should; anything else is a failure to talk to it
            if case ControlError.remote = error {} else { log("session \(id): could not \(doing): \(words)") }
            return .failure(Refusal(words: words))
        }
    }
}
