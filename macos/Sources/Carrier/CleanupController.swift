import CarrierCore
import Observation
import SwiftUI

/// What the Cleanup group of the Dictation page reads and does: the choices (kept in `AppPreferences`), whether the chosen server is running and which models it lists, and the Test.
@MainActor @Observable final class CleanupController {
    static let shared = CleanupController(client: LocalModelClient())

    enum ServerState: Equatable { case unknown, running(models: [String]), notRunning }
    enum TestState: Equatable { case idle, running, done(CleanupResult), failed(CleanupFailure) }

    private(set) var serverState = ServerState.unknown
    private(set) var test = TestState.idle
    @ObservationIgnored private let client: any TextModelClient
    @ObservationIgnored private let preferences: AppPreferences

    init(client: any TextModelClient, preferences: AppPreferences = AppPreferences()) {
        self.client = client
        self.preferences = preferences
    }

    var enabled: Bool { preferences.dictationCleanupEnabled }
    var server: CleanupServer? { preferences.dictationCleanupServer }
    var model: String? { preferences.dictationCleanupModel }
    var prompt: String { preferences.dictationCleanupPrompt }
    var canBeOn: Bool { cleanupCanBeOn(server: server, model: model) }

    func setEnabled(_ on: Bool) { preferences.dictationCleanupEnabled = on && canBeOn }
    func set(prompt: String) { preferences.dictationCleanupPrompt = prompt }
    func choose(model: String?) {
        preferences.dictationCleanupModel = model
        if model == nil { preferences.dictationCleanupEnabled = false }
    }

    /// A model belongs to its server, so a new server leaves no model and Cleanup off.
    func choose(server: CleanupServer?) {
        preferences.dictationCleanupServer = server
        choose(model: nil)
    }

    /// Asks the chosen server for its models; a server that does not answer is not running. Clears the last Test, which was another setup.
    func refresh() async {
        test = .idle
        guard let server else { return serverState = .unknown }
        serverState = (try? await client.models(of: server)).map { .running(models: $0) } ?? .notRunning
    }

    /// Sends the sample with the prompt to the chosen model; the result or the cause shows in the group.
    func runTest() async {
        guard test != .running else { return }
        test = .running
        let run = CleanupRun(client: client)
        do {
            test = .done(try await run.run(server: server, model: model, prompt: prompt, text: cleanupSample))
        } catch {
            test = .failed(error as? CleanupFailure ?? .badReply(error.localizedDescription))
        }
    }
}
