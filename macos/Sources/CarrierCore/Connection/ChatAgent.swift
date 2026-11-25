import Foundation

public struct ChatAgent: Decodable, Equatable {
    public let name: String
    public let harness: String
    public let model: String?
    /// Whether the agent's binary was found on the host's machine.
    public let found: Bool
    /// The account of `providers.json` the agent runs on, which has its icon, color and label; nil from a host that does not say (the agent's
    /// name is the account's then, as the host names them when `chat.json` lists no agents).
    public let account: String?

    public init(name: String, harness: String, model: String? = nil, found: Bool, account: String? = nil) {
        self.name = name
        self.harness = harness
        self.model = model
        self.found = found
        self.account = account
    }
}

/// The account behind each chat agent, as the host last said (`SocketChatHost.agents`): the app looks an agent's icon, color and label up by it.
/// An agent not here is named as its account, as the host names them when `chat.json` lists no agents. It also keeps each agent's harness,
/// which is what its tool's mark is looked up by: an account named by the person has the name they gave, not the tool's.
public enum AgentAccounts {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var known: [String: String] = [:]
    nonisolated(unsafe) private static var harnesses: [String: String] = [:]

    static func remember(_ agents: [ChatAgent]) {
        let pairs = agents.compactMap { agent in agent.account.map { (agent.name, $0) } }
        lock.lock()
        defer { lock.unlock() }
        known = Dictionary(pairs, uniquingKeysWith: { first, _ in first })
        harnesses = Dictionary(agents.map { ($0.name, $0.harness) }, uniquingKeysWith: { first, _ in first })
    }

    /// The harness an agent runs on (`claude`, `codex`…), which its tool's mark is looked up by; an agent not known is its own name, as it was.
    public static func harness(of agent: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return harnesses[agent] ?? agent
    }

    public static func account(of agent: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        return known[agent] ?? agent
    }
}
