import Foundation

// The Cleanup of a dictation (docs/adr/0030): the person's one prompt and the text go to a model server on this Mac, and what comes back is the result.
// The port, the run and the rules here; the HTTP client is `LocalModelClient`.

/// The model servers Cleanup talks to, both on this Mac.
public enum CleanupServer: String, CaseIterable, Sendable {
    case lmStudio, ollama

    public var title: String { self == .lmStudio ? "LM Studio" : "Ollama" }
    /// Where the server listens by default. Always the loopback: nothing goes off this Mac.
    public var baseURL: URL { URL(string: self == .lmStudio ? "http://127.0.0.1:1234" : "http://127.0.0.1:11434")! }
}

/// Why a cleanup did not give text; each says its cause in words, for the page and for `dictation.log`.
public enum CleanupFailure: Error, Equatable, Sendable {
    case noServer, noModel, emptyPrompt, timeout
    case serverDown(CleanupServer)
    case badReply(String)

    public var message: String {
        switch self {
        case .noServer: "Choose a server first"
        case .noModel: "The model is not on the server: choose another one"
        case .emptyPrompt: "The prompt is empty"
        case .timeout: "The model did not answer in time"
        case .serverDown(let server): "\(server.title) is not running"
        case .badReply(let cause): cause
        }
    }
}

/// What Cleanup needs from a model server: the models it lists and one completion with a system message and a user message, no tools.
public protocol TextModelClient: Sendable {
    func models(of server: CleanupServer) async throws -> [String]
    func complete(server: CleanupServer, model: String, system: String, text: String, timeout: Duration) async throws -> String
}

public struct CleanupResult: Equatable, Sendable {
    public let text: String
    public let seconds: TimeInterval
}

/// One cleanup: checks what the person chose, calls the client and says how long it took by the clock it is given.
public struct CleanupRun: Sendable {
    public let client: any TextModelClient
    public let now: @Sendable () -> Date
    public let timeout: Duration

    public init(client: any TextModelClient, now: @escaping @Sendable () -> Date = { Date() }, timeout: Duration = .seconds(30)) {
        self.client = client
        self.now = now
        self.timeout = timeout
    }

    /// Throws a `CleanupFailure`, whatever the client threw.
    public func run(server: CleanupServer?, model: String?, prompt: String, text: String) async throws -> CleanupResult {
        guard let server else { throw CleanupFailure.noServer }
        guard let model, model.isEmpty == false else { throw CleanupFailure.noModel }
        guard prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { throw CleanupFailure.emptyPrompt }
        let start = now()
        let reply: String
        do {
            reply = try await client.complete(server: server, model: model, system: prompt, text: text, timeout: timeout)
        } catch let failure as CleanupFailure {
            throw failure
        } catch {
            throw CleanupFailure.badReply(error.localizedDescription)
        }
        let cleaned = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false else { throw CleanupFailure.badReply("The model answered with no text") }
        return CleanupResult(text: cleaned, seconds: now().timeIntervalSince(start))
    }
}

/// Cleanup can run only with a server and one of its models chosen.
public func cleanupCanBeOn(server: CleanupServer?, model: String?) -> Bool { server != nil && model?.isEmpty == false }

/// What the prompt says until the person writes their own.
public let defaultCleanupPrompt = Preference.dictationCleanupPrompt.defaultValue

/// What the Try it box sends: a dictation with fillers, a stutter, a false start and no punctuation or capitals.
public let cleanupSample = "um so basically what i wanted to say is that the the endpoint should return the data uh per day and not per hour you know i mean per day"
