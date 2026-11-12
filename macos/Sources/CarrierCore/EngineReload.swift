import Foundation

// Every save of `config.json` or `providers.json` ends by asking the running engine to apply it (docs/specs/settings-apply-without-restart.md).

/// What a writer calls after its own successful write, and only then: asks the engine to read its settings again. nil when it did, or when
/// there was no one to ask (Carrier stopped, an engine that does not list `reload`); else the engine's problem, the key named.
public typealias Reload = () -> String?

/// `Reload` for the engine at `socketPath`. Blocks until the engine has answered, which is quick: call it as the saves already do.
public func reloadEngine(socketPath: String = controlSocketPath()) -> String? {
    guard let client = ControlClient.connect(path: socketPath, timeout: 3) else { return nil }
    defer { client.close() }
    do {
        _ = try client.hello()
        _ = try client.reload()
        return nil
    } catch ControlError.remote(let problem) {
        return problem
    } catch {
        // an engine that quit or stopped answering is one that is not there: the file is written and it reads it when it starts
        FileHandle.standardError.write(Data("carrier: reload: \(error)\n".utf8))
        return nil
    }
}

/// What the page says when the file is saved and the engine did not apply it.
public func reloadRefusedWords(_ problem: String) -> String {
    "Saved, but Carrier kept its settings: \(problem)"
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
