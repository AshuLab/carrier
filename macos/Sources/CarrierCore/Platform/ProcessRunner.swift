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

/// Runs a program to its end. Throws when it cannot start.
public protocol ProcessRunner: Sendable {
    func run(_ command: ProcessCommand) async throws -> ProcessResult
}
