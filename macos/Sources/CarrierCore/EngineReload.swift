import Foundation

// Every save of `config.json` or `providers.json` ends by asking the running engine to apply it (docs/specs/settings-apply-without-restart.md).

/// What came of asking the engine to read its settings again.
public enum ReloadOutcome: Equatable, Sendable {
    /// the engine read the files and runs on them
    case applied
    /// there was no one to ask (Carrier stopped, or an engine that does not list `reload`): it reads the files when it starts
    case nobody
    /// the engine kept its settings; its problem, the key named
    case refused(String)
    /// an engine that was there did not answer (a timeout, a socket error): the file is written, and it reads it when it starts
    case noAnswer
}

/// What a writer calls after its own successful write, and only then: asks the engine to read its settings again.
public typealias Reload = () -> ReloadOutcome

/// `Reload` for the engine at `socketPath`. Blocks until the engine has answered, which is quick: a saver that runs for every edit
/// calls `reloadEngineInBackground` instead.
public func reloadEngine(socketPath: String = controlSocketPath()) -> ReloadOutcome {
    guard let client = ControlClient.connect(path: socketPath, timeout: 3) else { return .nobody }
    defer { client.close() }
    do {
        _ = try client.hello()
        return try client.reload() ? .applied : .nobody
    } catch ControlError.remote(let problem) {
        return .refused(problem)
    } catch {
        FileHandle.standardError.write(Data("carrier: reload: \(error)\n".utf8))
        return .noAnswer
    }
}

/// `reloadEngine` off the main thread, for a page that saves at every edit: `done` gets the words to show when the engine did not apply
/// the file (`reloadWords`), on the main actor, once it has answered.
public func reloadEngineInBackground(socketPath: String = controlSocketPath(), done: @escaping @MainActor (String?) -> Void) {
    Task.detached {
        let outcome = reloadEngine(socketPath: socketPath)
        await MainActor.run { done(reloadWords(outcome)) }
    }
}

/// What the page says when the file is saved and the engine did not apply it.
public func reloadRefusedWords(_ problem: String) -> String {
    "Saved, but Carrier kept its settings: \(problem)"
}

/// What the page says for an outcome that needs saying: nil when the engine applied the file or there was no one to ask.
public func reloadWords(_ outcome: ReloadOutcome) -> String? {
    switch outcome {
    case .applied, .nobody: nil
    case .refused(let problem): reloadRefusedWords(problem)
    case .noAnswer: "Saved, but Carrier did not answer: it will read the file when it starts."
    }
}

/// What the Behavior and Repos tabs save with: `edit` rewrites the file at `path`, read just now so a save of another tab in between is not
/// lost; `unusable` is what to say when it cannot be read or `edit` gives nothing. A written file is followed by `reload`.
public func saveConfig(path: String, unusable: String, edit: (Data) -> Data?, reload: Reload) -> RoleSave {
    let url = URL(fileURLWithPath: path)
    guard let current = try? Data(contentsOf: url), let updated = edit(current) else { return .failed(unusable) }
    do {
        try updated.write(to: url, options: .atomic)
        return written(reload)
    } catch {
        FileHandle.standardError.write(Data("carrier: saving \(path) failed: \(error)\n".utf8))
        return .failed("Could not save the config file: \(error.localizedDescription)")
    }
}
