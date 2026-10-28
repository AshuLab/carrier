import Foundation
import Observation

// The Archive page (docs/specs/sessions-in-the-app.md, "Archive"): what it lists and says as plain values, the menu of a session row,
// the questions it asks, and what archiving, restoring, deleting and clearing do through the chat host.

/// How the Archive is ordered. The host does not say when a session was archived (it only archives an idle one), so "date archived"
/// is the session's last activity.
public enum ArchiveSort: String, CaseIterable { case dateArchived, project }

/// What the page shows for the archived rows: the groups, the count under the title, which empty state when there is nothing to list,
/// and whether Clear sessions has something to delete.
public struct ArchivePage: Equatable {
    public var subtitle: String
    public var groups: [SessionGroup]
    public var emptyState: EmptyState?
    public var canClear: Bool
}

/// The archived rows only. By date archived: Last 30 days and Older (counted back from `now`); by project: one group per workspace
/// ordered by name ignoring case; newest first inside a group. A non-empty `query` matches the title, the workspace and the agent
/// ignoring case and lists the matches, newest first, in one group. The subtitle is "5 sessions" ("2 results" while searching) and
/// says nothing when nothing is archived; the page is "Nothing archived" then, "No sessions match" when a search finds none.
public func archivePage(_ rows: [SessionRow], by sort: ArchiveSort = .dateArchived, query: String = "", now: Date = Date()) -> ArchivePage {
    let archived = rows.filter(\.archived)
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let newest: (SessionRow, SessionRow) -> Bool = { $0.updatedAt > $1.updatedAt }
    func group(_ title: String, _ rows: [SessionRow]) -> SessionGroup? { rows.isEmpty ? nil : SessionGroup(title: title, rows: rows.sorted(by: newest)) }
    let groups: [SessionGroup]
    if query.isEmpty == false {
        let found = archived.filter { [$0.title, $0.workspace, $0.agent].contains { $0.localizedCaseInsensitiveContains(query) } }
        groups = group("Results", found).map { [$0] } ?? []
    } else {
        switch sort {
        case .dateArchived:
            let cutoff = now.addingTimeInterval(-30 * 86400)
            groups = [group("Last 30 days", archived.filter { $0.updatedAt >= cutoff }), group("Older", archived.filter { $0.updatedAt < cutoff })].compactMap { $0 }
        case .project:
            groups = Dictionary(grouping: archived, by: \.workspace).compactMap { group($0.key, $0.value) }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
    let shown = groups.reduce(0) { $0 + $1.rows.count }
    let subtitle = query.isEmpty == false ? (shown == 1 ? "1 result" : "\(shown) results") : archived.isEmpty ? "" : archived.count == 1 ? "1 session" : "\(archived.count) sessions"
    let empty: EmptyState? = groups.isEmpty ? (archived.isEmpty ? .nothingArchived : .noSessionsMatch) : nil
    return ArchivePage(subtitle: subtitle, groups: groups, emptyState: empty, canClear: archived.isEmpty == false)
}

/// What an alert says; its first button is the one that does nothing, and the default.
public struct Question: Equatable {
    public let title: String
    public let message: String
    public let confirm: String
}

/// What a worktree holds that deleting would lose, in words: "3 uncommitted files and 2 commits that exist nowhere else"; nil when it holds nothing.
private func lostWork(files: Int, commits: Int) -> String? {
    let dirty = files == 1 ? "1 uncommitted file" : "\(files) uncommitted files"
    let unpushed = commits == 1 ? "1 commit that exists nowhere else" : "\(commits) commits that exist nowhere else"
    switch (files > 0, commits > 0) {
    case (true, true): return "\(dirty) and \(unpushed)"
    case (true, false): return dirty
    case (false, true): return unpushed
    case (false, false): return nil
    }
}

/// Clear sessions: names how many will be deleted and, from the host's `deletePreview` of all of them, how many work in a worktree
/// that would lose work and the totals of files and commits; sessions in a base folder add nothing.
public func clearSessionsQuestion(count: Int, previews: [SessionDeletePreview] = []) -> Question {
    let worktrees = previews.compactMap(\.worktree)
    let losing = worktrees.filter { $0.dirty + $0.unpushed > 0 }
    var message = "Their transcripts are removed and cannot be brought back."
    if let lost = lostWork(files: losing.reduce(0) { $0 + $1.dirty }, commits: losing.reduce(0) { $0 + $1.unpushed }) {
        message += losing.count == 1
            ? " 1 of them works in a worktree that would lose work: \(lost) will be removed with it."
            : " \(losing.count) of them work in worktrees that would lose work: \(lost) will be removed with them."
    } else if worktrees.isEmpty == false {
        message += worktrees.count == 1 ? " 1 of them works in a worktree, which will be removed too." : " \(worktrees.count) of them work in worktrees, which will be removed too."
    }
    return Question(title: count == 1 ? "Delete the archived session?" : "Delete all \(count) archived sessions?", message: message, confirm: count == 1 ? "Delete" : "Delete all")
}

/// Delete on one archived row, with what the host says its worktree holds (nil for a session in a base folder, which keeps the plain text).
public func deleteSessionQuestion(_ row: SessionRow, worktree: SessionDeletePreview.Worktree? = nil) -> Question {
    var message = "Its transcript is removed and cannot be brought back."
    if let worktree {
        let removed = lostWork(files: worktree.dirty, commits: worktree.unpushed).map { "\($0) will be removed with its worktree." } ?? "Its worktree will be removed."
        message = removed + " " + message
    }
    return Question(title: "Delete \u{201C}\(row.title)\u{201D}?", message: message, confirm: "Delete")
}

/// What replaces the message box of an archived session, beside its Resume button.
public let archivedSessionNotice = "This session is archived: you are reading its transcript. Resume it to continue."

public enum SessionMenuAction: Equatable {
    case archive, restore, reveal(path: String), copy(String)
}

public struct SessionMenuItem: Equatable {
    public let title: String
    public let action: SessionMenuAction
}

/// The context menu of a session row in the sidebar and on the Sessions home: Archive (Restore for an archived match), Reveal in
/// Finder and Copy session id.
public func sessionMenu(_ row: SessionRow) -> [SessionMenuItem] {
    [
        SessionMenuItem(title: row.archived ? "Restore" : "Archive", action: row.archived ? .restore : .archive),
        SessionMenuItem(title: "Reveal in Finder", action: .reveal(path: row.folder)),
        SessionMenuItem(title: "Copy session id", action: .copy(row.id)),
    ]
}

/// Archives, restores and deletes sessions through the host. Each call returns what the host refused, in words, nil when it worked;
/// `changed` is told after a success so the lists are read again.
@Observable public final class SessionActions {
    @ObservationIgnored private let host: ChatHost
    @ObservationIgnored private let log: (String) -> Void
    @ObservationIgnored public var changed: () -> Void = {}

    public init(host: ChatHost, log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) }) {
        self.host = host
        self.log = log
    }

    public func archive(_ id: String) async -> String? { await run("archive", id) { try await $0.archive(id, true) } }

    public func restore(_ id: String) async -> String? { await run("restore", id) { try await $0.archive(id, false) } }

    public func delete(_ id: String) async -> String? { await run("delete", id) { try await $0.delete(id) } }

    /// What an alert before a delete is: the question to ask, or what the host refused when it was asked what the deletion would discard.
    public enum Confirmation: Equatable {
        case ask(Question)
        case refused(String)
    }

    /// Asks the host what deleting the session would discard and builds its question; the deletion must not go ahead without it.
    public func confirmDelete(_ row: SessionRow) async -> Confirmation {
        switch await preview("delete \(row.id)", [row.id]) {
        case .success(let previews): .ask(deleteSessionQuestion(row, worktree: previews.first { $0.sessionId == row.id }?.worktree))
        case .failure(let refusal): .refused(refusal.words)
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
    public func clear(_ ids: [String]) async -> String? {
        var deleted = 0
        var refusal: String?
        for id in ids {
            let failed = await delete(id)
            if let failed, refusal == nil { refusal = failed }
            if failed == nil { deleted += 1 } else if failed == ConversationModel.words(ControlError.closed) { break }
        }
        return refusal.map { "Deleted \(deleted) of \(ids.count) archived sessions. \($0)" }
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
        do {
            try await call(host)
        } catch {
            let words = ConversationModel.words(error)
            // a refusal is the host answering as it should; anything else is a failure to talk to it
            if case ControlError.remote = error {} else { log("session \(id): could not \(doing): \(words)") }
            return words
        }
        changed()
        return nil
    }
}
