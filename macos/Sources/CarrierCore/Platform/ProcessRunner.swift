import Foundation

// Starting a program is a thing only the platform does (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 2): the core and the models
// take this protocol and their tests take a fake; the implementation, on `Process`, is in `Carrier/Platform`.

/// A program to run, with what it is given: its arguments, its whole environment and what is written to its standard input.
public struct ProcessCommand: Equatable, Sendable {
    public var program: String
    public var arguments: [String]
    public var environment: [String: String]
    public var input: Data?
    /// Seconds the program has before it is ended.
    public var limit: TimeInterval

    public init(program: String, arguments: [String] = [], environment: [String: String] = [:], input: Data? = nil, limit: TimeInterval = 5) {
        (self.program, self.arguments, self.environment, self.input, self.limit) = (program, arguments, environment, input, limit)
    }
}

/// What a program printed on standard output and how it ended; `timedOut` when it was ended for taking longer than its limit.
public struct ProcessResult: Equatable, Sendable {
    public var output: String
    public var status: Int32
    public var timedOut: Bool

    public init(output: String, status: Int32, timedOut: Bool = false) {
        (self.output, self.status, self.timedOut) = (output, status, timedOut)
    }
}

/// A program started by `spawnDetached`: its exit code once it has ended, nil while it runs.
public protocol SpawnedProcess: Sendable {
    var exitCode: Int32? { get }
}

public protocol ProcessRunner: Sendable {
    /// Runs a program to its end, or to its time limit. Throws when it cannot start.
    func run(_ command: ProcessCommand) async throws -> ProcessResult
    /// Starts a program in a session of its own, so it outlives the app and has no terminal, with nothing on its standard input and its standard
    /// output and standard error going to the file `log` (made and emptied). Does not wait for it. Throws when it cannot start.
    func spawnDetached(_ command: ProcessCommand, log: String) throws -> any SpawnedProcess
    /// What the user's login shell finds (`node`, the `PATH`); nil when it gave no complete answer in time.
    func detectShell() async -> Detection?
}
