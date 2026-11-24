import Foundation

/// What the app reads off the machine for the Health tab: the installed `carrier`'s version and the chat host's socket and version.
public struct HostFacts: Equatable {
    public var installedVersion: String?
    public var hostRunning = false
    public var hostVersion: String?
    /// A host that said nothing readable is taken to report health, so its absence is not blamed on it.
    public var hostReportsHealth = true

    public init() {}
}

/// Asks the chat host's socket and the installed `carrier` what they are.
public struct HostProbe {
    let runner: any ProcessRunner
    let socket: any HostSocket

    public init(runner: any ProcessRunner, socket: any HostSocket) { (self.runner, self.socket) = (runner, socket) }

    /// The facts, from the socket of `command` (else the chat host's usual one); the installed version is asked fresh. Off the main thread.
    public func read(_ command: StartCommand?) async -> HostFacts {
        var facts = HostFacts()
        if let command { facts.installedVersion = await installedVersion(command) }
        switch socket.hello(at: command?.socketPath ?? chatSocketPath()) {
        case .nobody: break
        case .unreadable: facts.hostRunning = true
        case .said(let hello):
            facts.hostRunning = true
            facts.hostVersion = hello.version
            facts.hostReportsHealth = hello.capabilities.contains(.health)
        }
        return facts
    }

    /// What `carrier --version` prints; nil, with the reason in the log, when the command fails or prints something else.
    /// With `remembered` (the Homebrew `carrier`, whose upgrade changes the file it links to) the version is kept with the stamp of what ran
    /// (`rememberedVersion`), and the command, which starts a whole `node`, is not run again while the stamp is the same. A run from source is
    /// always asked: it reads `package.json`, which the stamp does not cover. So is the Health tab, which wants a fresh read.
    public func installedVersion(_ command: StartCommand, remembered: Bool = false) async -> String? {
        // the chat host's own arguments end with its subcommand; what comes before it (the script, for a `node` start) stays
        let asked = ProcessCommand(program: command.program, arguments: Array(command.arguments.dropLast()) + ["--version"], environment: command.environment)
        let run = { () async -> String? in
            do {
                let run = try await runner.run(asked)
                if run.status == 0, versionNumbers(run.output) != nil { return run.output.trimmingCharacters(in: .whitespacesAndNewlines) }
                let how = run.timedOut ? "did not answer in 5 seconds and was ended" : "failed (exit \(run.status)) or printed something else"
                FileHandle.standardError.write(Data("carrier: the chat host was left alone, `carrier --version` \(how)\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("carrier: the chat host was left alone, `carrier --version` could not run: \(error)\n".utf8))
            }
            return nil
        }
        guard remembered else { return await run() }
        return await rememberedVersion(stamp: { programStamp([command.program] + command.arguments.dropLast()) }, run: run)
    }
}
