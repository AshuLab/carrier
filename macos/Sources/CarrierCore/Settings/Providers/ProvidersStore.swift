import Foundation
import Observation

/// The last answer of `providers`; asked when the page opens and again on request, and only of a host that lists it.
@MainActor @Observable public final class ProvidersStore {
    public internal(set) var outcome = ProvidersOutcome.unasked
    /// Why the last Add did not write the account, in words; nil when it did or none was made.
    public private(set) var addProblem: String?
    /// Why the last Add account, edit or Remove did not write the file, in words naming the field; nil when it did or none was made.
    public private(set) var editProblem: String?
    /// What the engine answered to the last write when that is a plain fact and not a problem (an older engine reads the file when it starts); nil when it applied it or none was made.
    public private(set) var editNote: String?
    /// An Add is being written and the engine asked: its button waits for the answer, so a second click does not add twice. Save and Remove close at once.
    public private(set) var busy = false
    /// Whether the host knows the `label`, `icon` and `color` of an account (its hello lists `accountIdentity`). An older `carrier` refuses a
    /// `providers.json` that has them, accounts and all, so the editor does not offer them and writes none until it does.
    public private(set) var identityEditable = false
    /// Whether the host also knows the later icons and colors (`accountPalette`); an `accountIdentity` host refuses a file with one.
    public private(set) var paletteEditable = false
    /// Whether the host knows `textGenerators` (its hello lists it). An older `carrier` refuses a `providers.json` with the keys, so none is written until it does.
    public private(set) var generatorEditable = false
    /// Whether the host can title earlier sessions in the background (`regenerateTitles` in its hello).
    public private(set) var canRegenerateTitles = false
    /// True while `regenerateTitles` is waiting for the host's answer.
    public private(set) var retitling = false
    /// What the last `regenerateTitles` answered, or nil before it ran or after leaving or changing the generator.
    public private(set) var retitleOutcome: RetitleOutcome?

    @ObservationIgnored private let host: ChatHost
    @ObservationIgnored private let file: () -> ProvidersFile
    @ObservationIgnored private let log: (String) -> Void
    @ObservationIgnored private let status: ReloadStatus
    /// The look at the host after a write.
    @ObservationIgnored private var follow: Task<Void, Never>?

    /// `file` is looked up at each use, so the Carrier folder is the one the app has then; the app only reads it (a change is a request to `host`, ADR 0053).
    public init(
        host: ChatHost, file: @escaping () -> ProvidersFile = ProvidersFile.current,
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) },
        status: ReloadStatus? = nil
    ) {
        self.host = host
        self.file = file
        self.log = log
        self.status = status ?? .shared
    }

    /// When the app opens: with no `providers.json`, asks for one account per harness the host found, named after it. With a file there it asks for nothing, so an account that was removed stays removed; with nothing found
    /// it asks for nothing either (an empty file would leave the roles' default accounts undeclared), and a host that cannot answer is not guessed at.
    public func createFileIfMissing() async {
        guard file().exists == false else { return }
        await load()
        guard case .reply(let reply) = outcome, reply.problem == nil else { return }
        let found = reply.accounts.filter(\.found).map { DetectedAccount(name: $0.name, harness: $0.harness) }
        guard found.isEmpty == false, file().exists == false else { return }
        do {
            let saved = try await host.changeProviders(.setAccounts(found))
            status.record(saved.outcome)
            // no page is asking for this file, so the engine's refusal goes to the log
            if let problem = reloadWords(saved.outcome) { log("providers: the engine did not apply the new providers.json: \(problem)") }
        } catch {
            log("providers: could not create providers.json: \(error)")
            return
        }
        await load()
    }

    /// The Add of a "Found, not added" row: the account named after the harness, then the host is asked again so the row goes away.
    public func add(harness: String) async {
        busy = true
        defer { busy = false }
        addProblem = nil
        dismissProblem()
        do {
            let saved = try await host.changeProviders(.setAccounts([DetectedAccount(name: harness, harness: harness)]))
            // the row leaves "Found, not added" once the host is asked again, so the engine's words go where the accounts show them
            engineSaid(saved.outcome)
        } catch {
            addProblem = problem(error, "add \(harness)")
        }
        busy = false
        await load()
    }

    /// The person closed the form or editor that showed `editProblem`, or left the page.
    public func dismissProblem() {
        editProblem = nil
        editNote = nil
        retitleOutcome = nil
    }

    /// What the engine answered to a write: a problem is `editProblem`, a plain fact `editNote`. The answer is also the shared one, which other pages show.
    private func engineSaid(_ outcome: ReloadOutcome) {
        status.record(outcome)
        let words = reloadWords(outcome)
        editProblem = outcome.isProblem ? words : nil
        editNote = outcome.isProblem ? nil : words
    }

    /// What a failed request says: Carrier's own words for a refusal, a fixed sentence (the error goes to the log) for anything else.
    private func problem(_ error: Error, _ what: String) -> String {
        if case ControlError.remote(let refusal) = error { return refusal.text }
        log("providers: could not \(what): \(error)")
        return "providers.json could not be written; the file stays as it was."
    }

    /// A quiet line when another account of `harness` already has this config folder, which makes it the same login and not a new one; nil otherwise.
    public func sharedFolderNote(configDir: String, harness: String, except name: String? = nil) -> String? {
        let json = (try? file().read()).flatMap { $0 }
        return accountSharingFolder(configDir: configDir, harness: harness, except: name, in: json).map { "\($0) already uses this folder, so this is the same login, not another one." }
    }

    /// The Add account of a tool: a new account with a name and, when given, a config folder.
    @discardableResult public func addAccount(name: String, harness: String, configDir: String) async -> Bool {
        await change("add \(name)", .addAccount(name: name, harness: harness, configDir: configDir))
    }

    /// The editor's Save: the fields written to the account, an emptied one removing its key.
    @discardableResult public func save(name: String, draft: AccountDraft) async -> Bool {
        await change("save \(name)", .editAccount(name: name, draft: draft))
    }

    /// Remove: refused, naming who, while a role, a repo override, a failover list or a chat agent names the account.
    @discardableResult public func remove(name: String) async -> Bool {
        await change("remove \(name)", .removeAccount(name: name))
    }

    /// Choose the text generator (a model of a local server), or clear the choice with nil; written only while the host lists `textGenerators`.
    @discardableResult public func chooseTextGenerator(_ choice: (server: String, model: String)?) async -> Bool {
        guard generatorEditable else {
            editProblem = "The chat host does not know text generators yet. Update carrier (brew upgrade carrier) and restart the chat host."
            return false
        }
        retitleOutcome = nil
        return await change("choose a text generator", .setTextGenerator(choice.map { TextGeneratorChoice(server: $0.server, model: $0.model) }), showAtOnce: true)
    }

    /// Asks the host to title earlier sessions whose title is still their first line, in the background. Only sent while the host lists `regenerateTitles`.
    public func regenerateTitles() async {
        guard canRegenerateTitles else { return }
        retitling = true
        retitleOutcome = nil
        defer { retitling = false }
        do {
            retitleOutcome = .started(try await host.regenerateTitles())
        } catch {
            retitleOutcome = .refused(ConversationModel.words(error))
        }
    }

    /// Asks for the change and says what the engine did with the file; a refusal wrote nothing and says why. The editor closes when it gives back, and the host is looked at again after it
    /// (`settled`), in the background unless the page shows the result at once; a `problem` the host answers is what the page shows.
    private func change(_ what: String, _ request: ProvidersRequest, showAtOnce: Bool = false) async -> Bool {
        dismissProblem()
        let saved: ProvidersSaved
        do { saved = try await host.changeProviders(request) } catch {
            editProblem = problem(error, what)
            return false
        }
        engineSaid(saved.outcome)
        // the host reads the file at each use, so the page can show the choice the moment it is written
        if showAtOnce { await load() } else { follow = Task { await load() } }
        return true
    }

    /// Waits for the look at the host that follows the last write.
    public func settled() async { await follow?.value }

    public func load() async {
        let capabilities: Set<ControlClient.Capability>
        do { capabilities = try await host.capabilities() } catch {
            identityEditable = false
            paletteEditable = false
            generatorEditable = false
            canRegenerateTitles = false
            retitleOutcome = nil
            outcome = .noHost
            return
        }
        identityEditable = capabilities.contains(.accountIdentity)
        paletteEditable = capabilities.contains(.accountPalette)
        generatorEditable = capabilities.contains(.textGenerators)
        canRegenerateTitles = capabilities.contains(.regenerateTitles)
        if canRegenerateTitles == false { retitleOutcome = nil }
        guard capabilities.contains(.providers) else {
            outcome = .tooOld
            return
        }
        do { outcome = .reply(try await host.providers()) } catch {
            let reason = ConversationModel.words(error)
            log("providers: \(reason)")
            outcome = .failed(reason)
        }
    }
}
