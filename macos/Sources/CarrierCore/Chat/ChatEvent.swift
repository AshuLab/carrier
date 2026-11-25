import Foundation
import Observation

/// One of the provider's choices on an approval.
public struct ChatChoice: Codable, Equatable {
    public let id: String
    public let label: String
    public let allow: Bool

    public init(id: String, label: String, allow: Bool) {
        self.id = id
        self.label = label
        self.allow = allow
    }
}

/// One question of an `AskUserQuestion` approval: a short header, the question, the options the provider lists (the person may also
/// write their own) and whether more than one can be picked.
public struct ChatQuestion: Codable, Equatable {
    public struct Option: Codable, Equatable {
        public let label: String
        public let description: String
        /// Optional text (a mockup, a snippet) to show while the option is focused.
        public let preview: String?

        public init(label: String, description: String, preview: String? = nil) {
            self.label = label
            self.description = description
            self.preview = preview
        }
    }

    public let question: String
    public let header: String
    public let options: [Option]
    public let multiSelect: Bool

    public init(question: String, header: String, options: [Option], multiSelect: Bool = false) {
        self.question = question
        self.header = header
        self.options = options
        self.multiSelect = multiSelect
    }
}

/// An event of the conversation as the host stores it (docs/specs/chat-host.md, Decisions): `kind` says which of the fields are there.
public struct ChatEvent: Codable, Equatable {
    public let id: Int
    /// Milliseconds since the epoch.
    public let at: Int
    public let kind: String
    public var text: String?
    public var callId: String?
    public var tool: String?
    public var arg: String?
    public var output: [String]?
    public var status: String?
    public var approvalId: String?
    public var choices: [ChatChoice]?
    public var choiceId: String?
    /// An approval that asks questions (`AskUserQuestion`) lists them here; `arg` is absent then.
    public var questions: [ChatQuestion]?
    /// What the person answered to those, by question text (more than one pick comma-separated); on an `approval_answered`.
    public var answers: [String: String]?
    public var outcome: String?
    public var model: String?
    /// As the provider reported it: its keys differ (`input_tokens` or `inputTokens`), and any of them can be missing.
    public var usage: [String: Double]?
    /// A `step` event of a session's preparation: which step, and (in `status`, `running`, `done` or `failed`) how it stands; `detail` is the reason a step failed.
    public var step: String?
    public var detail: String?
    /// An `action` step is one of a project's actions: its name, and the moment it runs at (`afterClone` or `newWorktree`). Nil for any other event.
    public var action: String?
    public var when: String?
    /// The call that launched the subagent this event was made in; nil for the main agent's own. The main conversation does not draw an event that has one.
    public var parentCallId: String?
    /// A `task` event, the life of a subagent joined to its launching call by `callId`: `taskId` is what stopping it takes, `state` is
    /// `started`, `progress`, `completed`, `failed` or `stopped`. Its title and step are in `text` and `lastTool`; `parentCallId` is the
    /// call of the subagent that launched this one.
    public var taskId: String?
    public var state: String?
    public var agentType: String?
    public var lastTool: String?
    public var tools: Int?
    public var tokens: Int?
    public var ms: Int?
    public var background: Bool?
    /// A `notice` that says the session changed agent: the agents as the host's config names them. Nil for any other event, and from a host that does not switch.
    public var switched: Switched?
    /// An `error` the provider says is an account out of usage: `usage_limit`. Nil for any other error, and from a host that does not say.
    public var reason: String?
    /// When that limit resets, in milliseconds since the epoch, when the provider gives a timestamp; never set with `resetText`.
    public var resetsAt: Int?
    /// When that limit resets, in the provider's own words, when it gives only those.
    public var resetText: String?
    /// A `compact` event, the provider summarizing the conversation to free context: `manual` (the person's `/compact`) or `auto`, nil when the provider does not say.
    public var trigger: String?
    /// The context, in tokens, before and after that summary; nil when the provider does not say. `ms` is how long it took.
    public var before: Double?
    public var after: Double?
    /// Set on a `compact` that failed, and only then: why. The context is as it was.
    public var error: String?
    /// The text code and parameters of the `text` of a `notice` or the `detail` of a `step`; nil on an event stored before the codes, which has its words only.
    public var code: String?
    public var params: [String: TextParam]?

    /// The `text` of a notice or the `detail` of a step (`words`) in the person's language: the copy of the event's code, else the words, which is all an event stored before the codes has.
    public func shown(_ words: String?, bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        words.map { shownText($0, code: code, params: params, bundle: bundle, locale: locale) }
    }

    /// The agents of a switch, as `chat.json` names them.
    public struct Switched: Codable, Equatable {
        public let from: String
        public let to: String
        /// The models they run, as the host says them: the old agent's last turn (else its option) and the new conversation's own; nil from a host that does not say.
        public let fromModel: String?
        public let toModel: String?

        public init(from: String, to: String, fromModel: String? = nil, toModel: String? = nil) {
            self.from = from
            self.to = to
            self.fromModel = fromModel
            self.toModel = toModel
        }
    }

    public init(
        id: Int, at: Int, kind: String, text: String? = nil, callId: String? = nil, tool: String? = nil, arg: String? = nil, output: [String]? = nil,
        status: String? = nil, approvalId: String? = nil, choices: [ChatChoice]? = nil, choiceId: String? = nil, outcome: String? = nil,
        model: String? = nil, usage: [String: Double]? = nil, step: String? = nil, detail: String? = nil, action: String? = nil, when: String? = nil, questions: [ChatQuestion]? = nil,
        answers: [String: String]? = nil, parentCallId: String? = nil, taskId: String? = nil, state: String? = nil, agentType: String? = nil,
        lastTool: String? = nil, tools: Int? = nil, tokens: Int? = nil, ms: Int? = nil, background: Bool? = nil, switched: Switched? = nil, reason: String? = nil, resetsAt: Int? = nil, resetText: String? = nil,
        trigger: String? = nil, before: Double? = nil, after: Double? = nil, error: String? = nil,
        code: String? = nil, params: [String: TextParam]? = nil
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.text = text
        self.callId = callId
        self.tool = tool
        self.arg = arg
        self.output = output
        self.status = status
        self.approvalId = approvalId
        self.choices = choices
        self.choiceId = choiceId
        self.questions = questions
        self.answers = answers
        self.outcome = outcome
        self.model = model
        self.usage = usage
        self.step = step
        self.detail = detail
        self.action = action
        self.when = when
        self.parentCallId = parentCallId
        self.taskId = taskId
        self.state = state
        self.agentType = agentType
        self.lastTool = lastTool
        self.tools = tools
        self.tokens = tokens
        self.ms = ms
        self.background = background
        self.switched = switched
        self.reason = reason
        self.resetsAt = resetsAt
        self.resetText = resetText
        self.trigger = trigger
        self.before = before
        self.after = after
        self.error = error
        self.code = code
        self.params = params
    }
}
