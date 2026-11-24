import Foundation
import Observation

// What the chat host says of the machine (docs/specs/health-check-in-the-app.md): the state of `git`, `gh` and each chat agent's CLI,
// asked when the app opens, when it becomes active again and on an explicit refresh, and only of a host that lists `health`.

/// What one check comes to, in the host's words. `unknown`, the probe could not answer, never blocks.
public enum ToolState: String, Decodable, Equatable {
    case ready, missing, signedOut, unknown

    /// A state this app does not know (a newer host) reads as `unknown`.
    public init(from decoder: Decoder) throws {
        self = ToolState(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }

    /// Whether something in this state cannot be used: `missing` and `signedOut`.
    public var blocks: Bool { self == .missing || self == .signedOut }
}

/// The reply of `health`: only verdicts, never an email, an organisation or a token.
public struct HostHealth: Decodable, Equatable {
    public struct Agent: Decodable, Equatable {
        public let name: String
        public let harness: String
        public let state: ToolState

        public init(name: String, harness: String, state: ToolState) {
            self.name = name
            self.harness = harness
            self.state = state
        }
    }

    public let git: ToolState
    public let gh: ToolState
    public let agents: [Agent]

    public init(git: ToolState, gh: ToolState, agents: [Agent]) {
        self.git = git
        self.gh = gh
        self.agents = agents
    }
}

/// The moments the app asks for the health.
public enum HealthMoment: CaseIterable {
    case open, active, refresh

    /// The host keeps its answer for thirty seconds; coming back from Terminal (where the person may have just logged in) and pressing
    /// Check again want a fresh one.
    public var refreshes: Bool { self != .open }
}

/// Whether to ask at that moment: only of a host that lists `health`, so an older one is left as before.
public func shouldAskHealth(_ moment: HealthMoment, capabilities: Set<ControlClient.Capability>) -> Bool {
    capabilities.contains(.health)
}

/// The last health the host answered; nil until it did, and again for a host that does not list `health`.
@MainActor @Observable public final class HealthStore {
    public private(set) var latest: HostHealth?

    @ObservationIgnored private let host: ChatHost
    @ObservationIgnored private let log: (String) -> Void

    public init(host: ChatHost, log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) }) {
        self.host = host
        self.log = log
    }

    public func check(_ moment: HealthMoment) async {
        let capabilities: Set<ControlClient.Capability>
        // a host that is not running is the usual case before it starts: nothing to ask, and the last answer stands
        do { capabilities = try await host.capabilities() } catch { return }
        guard shouldAskHealth(moment, capabilities: capabilities) else {
            latest = nil
            return
        }
        do { latest = try await host.health(refresh: moment.refreshes) } catch {
            log("health: \(ConversationModel.words(error))")
        }
    }
}
