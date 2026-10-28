import Foundation
import Observation

// The draft of a new session (docs/specs/sessions-in-the-app.md, "New session"): the recent folders and the agents it offers, the
// sentence that says where the session works, and the model that opens the session and sends the first message. Nothing exists
// until that message is sent. What the sentence says about the branch, uncommitted changes and non-git folders is the worktrees epic's.

/// A folder the workspace picker offers: its last component and its full path.
public struct RecentFolder: Equatable {
    public let name: String
    public let path: String
}

/// The distinct base folders of the sessions the host lists (`workspace.base` for a session in a worktree, its folder otherwise),
/// the most recently active first, at most `limit`. `sessions` are the active and the archived ones together.
public func recentFolders(_ sessions: [ChatSession], limit: Int = 8) -> [RecentFolder] {
    var seen: Set<String> = []
    var folders: [RecentFolder] = []
    for session in sessions.sorted(by: { $0.lastActiveAt > $1.lastActiveAt }) {
        let path = session.workspace?.base ?? session.folder
        guard seen.insert(path).inserted else { continue }
        folders.append(RecentFolder(name: URL(fileURLWithPath: path).lastPathComponent, path: path))
        if folders.count == limit { break }
    }
    return folders
}

/// An entry of the agent chip's menu: one whose binary was not found is listed, disabled, with "not installed".
public struct AgentChoice: Equatable {
    public let name: String
    public let available: Bool
    public var note: String? { available ? nil : "not installed" }
}

public func agentChoices(_ agents: [ChatAgent]) -> [AgentChoice] { agents.map { AgentChoice(name: $0.name, available: $0.found) } }

/// The sentence above the box; until a folder is chosen it says "Choose a workspace…".
public func workSentence(folder: String?) -> String {
    "Work in \(folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Choose a workspace…") on the base folder"
}

/// A first message whose send failed after `open` made the session.
public struct FailedFirstSend: Equatable {
    public let text: String
    public let reason: String
}

/// The draft: loads what it offers, and `send()` opens the session and then sends the message, in two steps.
@MainActor @Observable public final class NewSessionModel {
    public private(set) var recent: [RecentFolder] = []
    public private(set) var agents: [AgentChoice] = []
    /// The chosen workspace's path, nil until one is chosen.
    public private(set) var folder: String?
    public var agent: String?
    public var text = ""
    public private(set) var sending = false
    /// Why `open` was refused (or the host would not start), said in words in the draft; nil when it worked.
    public private(set) var refusal: String?

    @ObservationIgnored private let host: ChatHost
    @ObservationIgnored private let ensureHost: @MainActor () async -> Bool
    @ObservationIgnored private let log: (String) -> Void
    /// What a conversation shows when its first message failed to send, by session id, until it takes it.
    @ObservationIgnored private var failedFirstSends: [String: FailedFirstSend] = [:]

    /// `ensureHost` starts the chat host when it is not running (#503) and says whether it answers now.
    public init(
        host: ChatHost, ensureHost: @escaping @MainActor () async -> Bool = { true },
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) }
    ) {
        self.host = host
        self.ensureHost = ensureHost
        self.log = log
    }

    /// Reads the agents and the recent folders again, each time the draft opens; a host that does not answer leaves what was there.
    public func load() async {
        do {
            agents = agentChoices(try await host.agents())
            recent = recentFolders(try await host.list(archived: false) + (try await host.list(archived: true)))
        } catch {
            log("new session: \(ConversationModel.words(error))")
        }
        if agents.contains(where: { $0.name == agent && $0.available }) == false { agent = agents.first(where: \.available)?.name }
    }

    public func choose(folder path: String) { folder = path }

    public var sentence: String { workSentence(folder: folder) }

    public var canSend: Bool {
        folder != nil && agent != nil && sending == false && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// Opens the session and sends the message; returns the session's id to select, nil when `open` was refused (the draft keeps
    /// the text and says why). A `send` that fails after `open` still returns the id: the session exists and its conversation shows the failure.
    public func send() async -> String? {
        guard canSend, let folder, let agent else { return nil }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        refusal = nil
        defer { sending = false }
        guard await ensureHost() else {
            refusal = hostNotRunning
            return nil
        }
        let id: String
        do {
            id = try await host.open(agent: agent, folder: folder)
        } catch {
            refusal = report(error, "open the session")
            return nil
        }
        do {
            try await host.send(id, message)
        } catch {
            failedFirstSends[id] = FailedFirstSend(text: message, reason: report(error, "send the first message"))
        }
        text = ""
        return id
    }

    /// The failure of a session's first send, handed over once to the conversation that shows it.
    public func takeFailure(of id: String) -> FailedFirstSend? { failedFirstSends.removeValue(forKey: id) }

    private func report(_ error: Error, _ doing: String) -> String {
        let message = ConversationModel.words(error)
        // a refusal is the host answering as it should; anything else is a failure to talk to it
        if case ControlError.remote = error { return message }
        log("new session: could not \(doing): \(message)")
        return message
    }
}
