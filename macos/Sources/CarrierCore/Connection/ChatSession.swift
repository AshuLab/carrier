import Foundation

/// A session as the host's `list` carries it: times are milliseconds since the epoch.
public struct ChatSession: Decodable, Equatable, Sendable {
    public enum State: String, Decodable, Sendable { case working, waitingApproval = "waiting_approval", idle, preparing }
    /// Whether the host is preparing the session from its plan, or a step failed; nil for a session that is not (or a host that does not say).
    public enum Preparation: String, Decodable, Sendable { case running, failed }

    public let id: String
    public let agent: String
    public let harness: String
    public let folder: String
    public let title: String?
    public let state: State
    public let createdAt: Int
    public let lastActiveAt: Int
    public let archived: Bool
    /// Set for a session in a worktree: `base` is the repository's folder, which is where the session is grouped. The host says
    /// `{kind: "folder"}` for a session in the base folder itself, which is nil here.
    public let workspace: Workspace?
    /// Whether the session's agent process runs: a closed one is resumed before a message is sent to it.
    public let live: Bool
    public let preparation: Preparation?
    /// True while the clock spares the session because its worktree holds unsaved work. A host that leaves it out is not keeping it.
    public let kept: Bool
    /// When the clock deletes the session, in milliseconds since the epoch; nil when it will not, and from a host that leaves it out.
    public let deleteAt: Int?
    /// What the agent last wrote, on one line and cut; nil before it answered, and from a host or a reply that leaves it out.
    public let lastMessage: String?
    /// The turns that finished, and the model of the last; zero and nil from a host or a reply that leaves them out.
    public let turns: Int
    public let model: String?
    /// Whether the host said anything of how the session went: an older one does not, and then no message is not "no reply yet".
    public let reportsActivity: Bool
    /// The lines it changed and its pull request: nil from a host that does not say, while none is known, or for a value this app does not know.
    public let diff: SessionDiff?
    public let pullRequest: SessionPullRequest?
    /// What the agent waits for after its turn ended; empty from a host that does not say.
    public let background: [BackgroundTask]
    /// The session that started this one by delegating, for a child session; nil for any other, and from a host that does not say.
    public let parentSessionId: String?
    /// The child sessions this one started, oldest first; empty from a host that does not say. The list of sessions leaves the children themselves out.
    public let children: [Child]
    /// The harnesses the session has run turns on, in the order it first used them; a session that changed agent has more than one. Just its own
    /// harness from a host that does not say.
    public let providers: [String]

    /// A child session as its parent lists it. `level` is the permission level it runs at (0 reads only, 1 asks before each change, 2 edits without asking), nil when the host does not say.
    public struct Child: Decodable, Equatable, Sendable {
        public let id: String
        public let agent: String
        public let harness: String
        public let state: State
        public let level: Int?
        /// True while the child waits for an approval or a question.
        public let needsPerson: Bool
    }

    public struct Workspace: Decodable, Equatable, Sendable {
        public let base: String
        public let branch: String?
        /// The branch the worktree was cut from.
        public let from: String?
    }

    private enum CodingKeys: String, CodingKey { case id, agent, harness, folder, title, state, createdAt, lastActiveAt, archived, workspace, live, preparation, kept, deleteAt, lastMessage, turns, model, parentSessionId, children, diff, pr, background, providers }
    private struct Kind: Decodable {
        let kind: String
        let base: String?
        let branch: String?
        let from: String?
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        agent = try values.decode(String.self, forKey: .agent)
        harness = try values.decode(String.self, forKey: .harness)
        folder = try values.decode(String.self, forKey: .folder)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        state = try values.decode(State.self, forKey: .state)
        createdAt = try values.decode(Int.self, forKey: .createdAt)
        lastActiveAt = try values.decode(Int.self, forKey: .lastActiveAt)
        archived = try values.decode(Bool.self, forKey: .archived)
        live = try values.decode(Bool.self, forKey: .live)
        // a value this app does not know is no preparation, as a host that leaves the field out
        preparation = (try? values.decodeIfPresent(Preparation.self, forKey: .preparation)) ?? nil
        kept = try values.decodeIfPresent(Bool.self, forKey: .kept) ?? false
        deleteAt = try values.decodeIfPresent(Int.self, forKey: .deleteAt)
        lastMessage = try values.decodeIfPresent(String.self, forKey: .lastMessage)
        turns = try values.decodeIfPresent(Int.self, forKey: .turns) ?? 0
        reportsActivity = values.contains(.turns)
        model = try values.decodeIfPresent(String.self, forKey: .model)
        // a shape this app does not know is no data, never a list it cannot read
        diff = (try? values.decodeIfPresent(SessionDiff.self, forKey: .diff)) ?? nil
        pullRequest = (try? values.decodeIfPresent(SessionPullRequest.self, forKey: .pr)) ?? nil
        background = (try? values.decodeIfPresent([BackgroundTask].self, forKey: .background)) ?? []
        parentSessionId = try values.decodeIfPresent(String.self, forKey: .parentSessionId)
        children = try values.decodeIfPresent([Child].self, forKey: .children) ?? []
        let used = try values.decodeIfPresent([String].self, forKey: .providers) ?? []
        providers = used.isEmpty ? [harness] : used
        let placed = try values.decodeIfPresent(Kind.self, forKey: .workspace)
        guard let placed, placed.kind == "worktree" else { workspace = nil; return }
        guard let base = placed.base else { throw DecodingError.keyNotFound(CodingKeys.workspace, .init(codingPath: decoder.codingPath, debugDescription: "a worktree without its base folder")) }
        workspace = Workspace(base: base, branch: placed.branch, from: placed.from)
    }
}
