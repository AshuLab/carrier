import Foundation
import Observation

/// What the summary of an `events` reply says of its session, the part of a row of `list` a conversation reads: its agent, whether it is in the archive,
/// whether its agent process runs and what the agent waits for in the background.
public struct SessionFacts: Equatable {
    public let agent: String?
    public let archived: Bool
    public let live: Bool
    public let background: [BackgroundTask]
    /// The folder the session works from: its worktree's base folder, else its own folder; nil from a host that does not say.
    public let baseFolder: String?

    public init(agent: String? = nil, archived: Bool = false, live: Bool, background: [BackgroundTask] = [], baseFolder: String? = nil) {
        (self.agent, self.archived, self.live, self.background, self.baseFolder) = (agent, archived, live, background, baseFolder)
    }
}

/// The reply of `events`: the page after the cursor, the cursor to ask from next and the text of the message being written.
/// The session's state (from its summary) comes with it, as the model needs to know whether the agent is answering; so do the ids
/// of the approvals still pending (the ones the person can answer) and the options, which the slice that draws them reads.
public struct ChatEvents: Decodable, Equatable {
    public let events: [ChatEvent]
    public let cursor: Int
    public let streaming: String
    public let state: ChatSession.State?
    public let pending: Set<String>
    /// What the provider offers for this session, with the current values; empty for a closed session.
    public let options: [ChatOption]
    /// What the provider lets the person invoke; empty for a closed session.
    public let commands: [ChatCommand]
    /// How the session's preparation stands (from its summary), nil when it is not being prepared or the host does not say.
    public let preparation: ChatSession.Preparation?
    /// What the session's summary says of the session itself, so the model asks for no list; nil from a host that does not say whether it runs.
    public let facts: SessionFacts?
    /// The latest line of git's own progress while a clone runs; nil when there is none or the host leaves it out.
    public let progress: String?
    /// The host's name for this version of `options` and `commands`; nil from a host that does not say. Sent back in the next request, it makes
    /// the host leave both out while they stay as they are.
    public let listsRev: String?
    /// The host left `options` and `commands` out because they are the ones of `listsRev`, which the caller sent: they are empty here, not gone.
    public let listsUnchanged: Bool

    public init(
        events: [ChatEvent], cursor: Int, streaming: String = "", state: ChatSession.State? = nil, pending: Set<String> = [], options: [ChatOption] = [],
        commands: [ChatCommand] = [], preparation: ChatSession.Preparation? = nil, facts: SessionFacts? = nil, progress: String? = nil, listsRev: String? = nil, listsUnchanged: Bool = false
    ) {
        self.events = events
        self.cursor = cursor
        self.streaming = streaming
        self.state = state
        self.pending = pending
        self.options = options
        self.commands = commands
        self.preparation = preparation
        self.facts = facts
        self.progress = progress
        self.listsRev = listsRev
        self.listsUnchanged = listsUnchanged
    }

    /// The same reply with the lists the caller kept for `listsRev`, when the host left them out.
    func with(options: [ChatOption], commands: [ChatCommand]) -> ChatEvents {
        ChatEvents(
            events: events, cursor: cursor, streaming: streaming, state: state, pending: pending, options: options, commands: commands,
            preparation: preparation, facts: facts, progress: progress, listsRev: listsRev, listsUnchanged: false
        )
    }

    private enum CodingKeys: String, CodingKey { case events, cursor, streaming, session, approvals, options, commands, progress, listsRev, listsUnchanged }
    private struct Summary: Decodable {
        let state: ChatSession.State
        let preparation: ChatSession.Preparation?
        /// Only a host that says whether the session runs (`live`) gives these: with an older one the model reads the lists.
        let facts: SessionFacts?
        private struct Placed: Decodable {
            let kind: String
            let base: String?
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            state = try values.decode(ChatSession.State.self, forKey: .state)
            preparation = (try? values.decodeIfPresent(ChatSession.Preparation.self, forKey: .preparation)) ?? nil
            if let live = try? values.decodeIfPresent(Bool.self, forKey: .live) {
                facts = SessionFacts(
                    agent: try? values.decodeIfPresent(String.self, forKey: .agent), archived: (try? values.decodeIfPresent(Bool.self, forKey: .archived)) ?? false,
                    live: live, background: (try? values.decodeIfPresent([BackgroundTask].self, forKey: .background)) ?? [],
                    baseFolder: Self.base(values)
                )
            } else {
                facts = nil
            }
        }

        /// A worktree session works from its base folder, any other from its own folder.
        private static func base(_ values: KeyedDecodingContainer<CodingKeys>) -> String? {
            if let placed = (try? values.decodeIfPresent(Placed.self, forKey: .workspace)) ?? nil, placed.kind == "worktree", let base = placed.base { return base }
            return (try? values.decodeIfPresent(String.self, forKey: .folder)) ?? nil
        }

        private enum CodingKeys: String, CodingKey { case state, preparation, agent, archived, live, background, folder, workspace }
    }
    private struct Approval: Decodable { let approvalId: String }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        events = try values.decode([ChatEvent].self, forKey: .events)
        cursor = try values.decode(Int.self, forKey: .cursor)
        streaming = try values.decode(String.self, forKey: .streaming)
        let summary = try values.decodeIfPresent(Summary.self, forKey: .session)
        state = summary?.state
        preparation = summary?.preparation
        facts = summary?.facts
        progress = try values.decodeIfPresent(String.self, forKey: .progress)
        pending = Set(try values.decodeIfPresent([Approval].self, forKey: .approvals)?.map(\.approvalId) ?? [])
        options = try values.decodeIfPresent([ChatOption].self, forKey: .options) ?? []
        commands = try values.decodeIfPresent([ChatCommand].self, forKey: .commands) ?? []
        listsRev = try values.decodeIfPresent(String.self, forKey: .listsRev)
        listsUnchanged = try values.decodeIfPresent(Bool.self, forKey: .listsUnchanged) ?? false
    }
}
