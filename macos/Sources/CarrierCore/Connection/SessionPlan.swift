import Foundation

/// Where a plan works: a folder that exists, a repository `owner/name` (the host clones it into its projects folder when the message is sent, or
/// fetches it when it is there already), or a new project of this name (the host makes `<projects folder>/local/<name>` when the message is sent). A new
/// project keeps `project` as its `kind` on the wire, since an older host refuses another value.
public enum PlanWorkspace: Equatable {
    case folder(String)
    case repo(String)
    case newProject(String)
}

/// What a new session is before it exists (docs/adr/0018): where it works, the agent and the options the person chose (an id and a value each,
/// as `agentOptions` listed them), the first message and the branch to check out, or for a worktree the branch it starts from and its name.
public struct SessionPlan: Equatable {
    public let agent: String
    public let workspace: PlanWorkspace
    /// The branch to check out in the folder, when the person picked one other than the checked-out one and asked for no worktree.
    public let branch: String?
    public let worktree: WorktreeRequest?
    public let options: [String: String]
    public let text: String

    /// The folder of a plan for a folder; nil for a repository or a new project.
    public var folder: String? {
        if case .folder(let path) = workspace { return path }
        return nil
    }

    public init(agent: String, folder: String, branch: String? = nil, worktree: WorktreeRequest? = nil, options: [String: String] = [:], text: String) {
        self.init(agent: agent, workspace: .folder(folder), branch: branch, worktree: worktree, options: options, text: text)
    }

    public init(agent: String, workspace: PlanWorkspace, branch: String? = nil, worktree: WorktreeRequest? = nil, options: [String: String] = [:], text: String) {
        self.agent = agent
        self.workspace = workspace
        self.branch = branch
        self.worktree = worktree
        self.options = options
        self.text = text
    }

    /// The plan as the host's request takes it; every string goes on the wire JSON-encoded.
    var wire: String {
        let place = switch workspace {
        case .folder(let path): "{\"kind\":\"folder\",\"folder\":\(jsonString(path))}"
        case .repo(let name): "{\"kind\":\"repo\",\"repo\":\(jsonString(name))}"
        case .newProject(let name): "{\"kind\":\"project\",\"name\":\(jsonString(name))}"
        }
        var fields = [
            "\"workspace\":\(place)", "\"agent\":\(jsonString(agent))", "\"text\":\(jsonString(text))",
        ]
        if options.isEmpty == false { fields.append("\"options\":{" + options.sorted { $0.key < $1.key }.map { "\(jsonString($0.key)):\(jsonString($0.value))" }.joined(separator: ",") + "}") }
        // a worktree is cut from the branch, so the one field serves both
        if let branch = worktree?.from ?? branch { fields.append("\"branch\":\(jsonString(branch))") }
        if let worktree {
            let inside = [worktree.name.map { "\"name\":\(jsonString($0))" }, worktree.startFrom.map { "\"startFrom\":\"\($0.rawValue)\"" }].compactMap { $0 }
            fields.append("\"worktree\":{" + inside.joined(separator: ",") + "}")
        }
        return "{" + fields.joined(separator: ",") + "}"
    }
}

/// What an agent offers before a session exists.
public struct AgentOffer: Codable, Equatable {
    public let options: [ChatOption]
    public let commands: [ChatCommand]

    public init(options: [ChatOption] = [], commands: [ChatCommand] = []) {
        self.options = options
        self.commands = commands
    }

    private enum CodingKeys: String, CodingKey { case options, commands }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        options = try values.decodeIfPresent([ChatOption].self, forKey: .options) ?? []
        commands = try values.decodeIfPresent([ChatCommand].self, forKey: .commands) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(options, forKey: .options)
        try values.encode(commands, forKey: .commands)
    }
}

/// The reply of `switchAgent`: the session as it is now (it has no `live` or the activity of a listed one, so it is not a `ChatSession`) and the new agent's options.
public struct AgentSwitch: Decodable, Equatable {
    public struct Session: Decodable, Equatable {
        public let id: String
        public let agent: String
        public let harness: String
        public let state: ChatSession.State
    }

    public let session: Session
    public let options: [ChatOption]
}
