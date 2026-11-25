import CarrierCore
import Foundation

extension EngineConfigSender {
    /// The app's: the engine's socket, and `carrier config` through the setup the app starts Carrier with when the engine does not answer.
    static var app: EngineConfigSender { EngineConfigSender(launcher: .app) }

    /// A change that is still waiting when the app quits, sent in place (the app is gone before a task would end): to the engine when it answers, else through `carrier config`.
    func sendBeforeQuit(_ change: EngineConfigChange) {
        if (try? sendToSocket(change)) != nil { return }
        guard var command = launcher?.command() else { return }
        command.input = change.request
        _ = try? shortRun(command.program, command.arguments, environment: command.environment, input: command.input, limit: command.limit)
    }
}

/// The role edits of the Agents page, a repo's role screens and the Engine page, one at a time and in the order they were made.
@MainActor private let roleEdits = EngineConfigQueue()

/// Sends a change of `engine.json` the pages make a field at a time and shows what the engine answered like a reload (`ReloadNote`): `.saved`, or why it was refused.
@MainActor func saveToEngine(_ change: EngineConfigChange) async -> RoleSave {
    await roleEdits.save(change, send: EngineConfigSender.app.send)
}
