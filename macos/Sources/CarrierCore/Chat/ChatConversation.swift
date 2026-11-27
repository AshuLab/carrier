import Foundation
import Observation

// An open session's conversation (docs/specs/sessions-in-the-app.md, "The conversation"): the model that polls by cursor and keeps the feed current.
// The events of the host's `events` reply are `ChatEvent.swift` and `ChatEventsReply.swift`, the feed of rows they make (a pure function) `FeedRow.swift`
// and `ChatFeed.swift`; the model's rounds, actions and sends are `ConversationModel+{Round,Actions,Delivery}.swift`.

/// The conversation of one open session: polls `events` by cursor while `run()` is running (the view runs it in a task that ends
/// when the person leaves the session), in pages of at most `ConversationModel.page`, and keeps the feed.
@MainActor @Observable public final class ConversationModel {
    public static let page = 200

    public let sessionId: String
    public internal(set) var rows: [FeedRow] = []
    /// Whether the first answer has arrived: until it does the view is loading, not empty.
    public internal(set) var loaded = false
    /// Why the last poll failed, nil when it worked; the polling goes on, as the host may come back.
    public internal(set) var failure: String?
    /// The `after` of the next request.
    public internal(set) var cursor = 0
    /// Whether new output scrolls the view to the end: the Follow new output setting, set by the view.
    public var followsOutput = true
    /// Whether the view is at the end of the conversation: the view reports it as the person scrolls.
    public var atEnd = true
    /// Counts the times the view is to scroll to the end: new output arrived while it follows and the person was at the end.
    public internal(set) var scrolls = 0
    /// When each message was written (ms since the epoch), by the id of its row; the message in progress has none yet.
    public internal(set) var times: [String: Int] = [:]
    /// Called when a turn fails with a quota error (the Usage page's quotas are then out of date).
    @ObservationIgnored public var onQuotaError: (@MainActor () -> Void)?
    /// What is typed in the box; kept in `memory` as it changes, so it is still there when the person comes back to the session.
    public var draft = "" {
        didSet { if draft != oldValue { memory.saveDraft(sessionId, draft) } }
    }
    /// Whether the agent is answering (or waiting for an approval): the host refuses a message then, so the box queues it and the send button is Stop.
    public internal(set) var busy = false
    /// The message typed while the agent answered: one at a time, sent when the turn ends.
    public internal(set) var queued: String? { didSet { if queued != oldValue { keepUnsent() } } }
    /// The long texts pasted into the box and the files dropped on it, which go with the next message; kept like the draft.
    public var pastes: [PastedEntry] = [] { didSet { if pastes != oldValue { keepUnsent() } } }
    public var files: [AttachedFile] = [] { didSet { if files != oldValue { keepUnsent() } } }
    /// Whether the host can switch the session to another agent (its hello lists `switchAgent`), the agents it could switch to, and whether a switch is
    /// under way. The panel of the message box lists the agents and changes one with `switchAgent`.
    public internal(set) var canSwitchAgent = false
    public internal(set) var switchTargets: [AgentChoice] = []
    public internal(set) var switching = false
    /// The agent the person picked in the panel: the session changes to it when the next message is sent (`deliver`), not when it is picked, so
    /// choosing and changing one's mind costs nothing and the handoff goes out with the message it is for. nil is the session's own.
    public internal(set) var pendingAgent: String?
    /// The session's agent, as the summary of the host's `events` names it (its list, for a host that does not say); what the app saw last until the first answer, empty for a session that was never seen.
    public internal(set) var agent = "" { didSet { if pendingAgent == agent { pendingAgent = nil } } }
    /// Whether the session's agent process runs; a session that is not live shows the closed notice and resumes when a message is sent.
    public internal(set) var live = true
    /// Whether the session is asleep: closed, and not on its way to another state (being archived, prepared or woken by a send). Only then the
    /// closed notice shows. It holds at once the first time the session is read; after that a session has to stay closed for a second, as
    /// archiving closes it a moment before the host says it is archived.
    public internal(set) var asleep = false
    /// Whether a send is waking the session.
    public internal(set) var waking = false
    /// Whether the session is idle and the folder it works from is gone (its project was deleted from disk): a notice shows and a send is refused. A worktree
    /// session is judged by its base folder, since a cleaned worktree's own folder is brought back by the next message.
    public internal(set) var folderGone = false
    /// The events the feed was built from, added up over every rebuild: a test tells a rebuild (all the events) from an append (one), as
    /// `Transcript.work` does for an epic.
    @ObservationIgnored var feedWork = 0
    @ObservationIgnored var closedSince: Date?
    @ObservationIgnored let folderExists: (String) -> Bool
    @ObservationIgnored var baseFolder: String?
    @ObservationIgnored var known = true
    @ObservationIgnored var preparingSession = false
    /// A worktree folder that comes back for a session that exists: the host reports the preparation as running while its actions run, though the session is not `preparing`.
    @ObservationIgnored var restoring = false
    static let settle: TimeInterval = 1
    /// Whether the session is in the archive: its transcript is read only and the box gives way to a notice with Resume.
    public internal(set) var archived = false
    /// What the agent waits for after its turn ended, from the summary of the host's `events` (its list, for an older host): the card over the box says it.
    public internal(set) var background: [BackgroundTask] = []
    /// Whether the host can stop one of those tasks by itself (it lists `stopTask`): read from its hello once.
    public internal(set) var canStopTask = false
    /// The tasks that are the model's own work (a subagent, a workflow): the cyan card over the box is given these alone.
    public var agentWork: [BackgroundTask] { background.filter(\.agentWork) }
    /// The grey card over the box for the background processes; nil when there is none.
    public var processesCard: ProcessesCard? { ProcessesCard(background, canStop: canStopTask) }
    /// The message whose send or resume the host refused, for the banner's Try again; nil with no refusal or when it was not a send.
    public internal(set) var refusedText: String?
    /// Why the last send, resume, stop or answer was refused, said under the box; nil when it worked.
    public internal(set) var refusal: Refusal?
    /// What the provider offers and the values it runs with, as the last `events` reply said: the pill follows this, never a request.
    public internal(set) var options: [ChatOption] = []
    /// Why the last change of an option was refused, said in the panel; nil when it worked.
    public internal(set) var optionRefusal: String?
    /// What the provider lets the person invoke in this session, as the last `events` reply said; empty for a closed session.
    public internal(set) var commands: [ChatCommand] = []
    /// What a closed session could invoke the last time it was seen running, kept like `remembered`.
    public internal(set) var rememberedCommands: [ChatCommand] = []
    /// The agent last written to `memory`, so a poll writes it only when it changed: a write to the defaults wakes every observer of them.
    @ObservationIgnored var savedAgent = ""
    /// What the box lists to invoke: the running agent's, else what it listed when it last ran; that too until the first answer, so the box
    /// does not fill in after the view appears.
    public var shownCommands: [ChatCommand] { commands.isEmpty ? rememberedCommands : commands }
    /// What a closed session offered the last time it was seen running, kept between runs of the app.
    public internal(set) var remembered: [ChatOption] = []
    /// The values chosen while the session is closed: the host cannot change them until its agent runs, so they wait and are applied
    /// when a message wakes the session.
    public internal(set) var wakeOptions: [String: String] = [:]
    /// What the box lists: what the provider offers while the agent runs, else what it offered last with the choices made since; that too
    /// until the first answer, so the selects are there from the first frame of a session the app has seen.
    public var shownOptions: [ChatOption] {
        // the picked agent lists its options once it has taken over, with the message
        if pendingAgent != nil { return [] }
        if options.isEmpty == false { return options }
        return remembered.map { option in
            guard let chosen = wakeOptions[option.id] else { return option }
            return ChatOption(id: option.id, label: option.label, values: option.values, current: chosen)
        }
    }
    /// The steps of the session's preparation, from its `step` events, while the host prepares it; empty once the agent answers.
    public internal(set) var steps: [StepRow] = []
    /// What the person sent as the first message of the session the draft opened, shown until the host's own record of it arrives (a failed
    /// step before the message leaves none) so the text is never lost.
    public internal(set) var firstMessage: String?
    /// The subagent view open over the conversation, rebuilt with the feed; nil with none open.
    public internal(set) var openSubagent: SubagentWork?
    /// The session's subagent launches and button state, rebuilt with the feed.
    public internal(set) var subagents: SubagentsList = .empty
    @ObservationIgnored var openCall: String?
    /// Whether the host lists `stopTask`, read from its hello once; false until then and for an older host.
    @ObservationIgnored var hostStops: Bool?
    /// Counts the sends, so a poll that began before one does not tell the model the agent is idle when it is not.
    @ObservationIgnored var sends = 0

    @ObservationIgnored let host: ChatHost
    /// Replaces the wait between two rounds (the tests'); without it the model waits in `nap`, which a change of who looks and a send cut short.
    @ObservationIgnored private let sleep: ((Duration) async throws -> Void)?
    @ObservationIgnored let nap = PollNap()
    @ObservationIgnored private let viewing: Viewing
    /// The rounds in a row that failed, for the wait to grow while the host does not answer.
    @ObservationIgnored var failures = 0
    @ObservationIgnored let log: (String) -> Void
    @ObservationIgnored let memory: OptionsMemory
    @ObservationIgnored var events: [ChatEvent] = []
    @ObservationIgnored var streaming = ""
    /// How the session's preparation stands: `failed` offers Try again, `running` offers Cancel; nil once the agent answered.
    public internal(set) var preparation: ChatSession.Preparation?
    /// What the host refused when the person asked to try the preparation again or to cancel it, in words.
    public internal(set) var preparationRefusal: String?
    @ObservationIgnored var progress: String?
    /// The approvals the host still waits for, from the last reply.
    @ObservationIgnored var pending: Set<String> = []
    /// The person's last message, which Try again sends again.
    @ObservationIgnored var lastUserText: String?

    public init(
        host: ChatHost, sessionId: String, sleep: ((Duration) async throws -> Void)? = nil,
        log: @escaping (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) },
        memory: OptionsMemory = .none, viewing: Viewing? = nil, folderExists: @escaping (String) -> Bool = projectFolderExists
    ) {
        self.folderExists = folderExists
        self.host = host
        self.sessionId = sessionId
        self.sleep = sleep
        self.viewing = viewing ?? .shared
        self.log = log
        self.memory = memory
        remembered = memory.load(sessionId)
        rememberedCommands = memory.loadCommands(sessionId)
        agent = memory.loadAgent(sessionId)
        savedAgent = agent
        draft = memory.loadDraft(sessionId)
        let kept = memory.loadUnsent(sessionId)
        pastes = kept.pastes.map { PastedEntry(text: $0) }
        files = kept.files
        queued = kept.queued
    }

    private func keepUnsent() { memory.saveUnsent(sessionId, Unsent(pastes: pastes.map(\.text), files: files, queued: queued)) }

    /// Polls until the task is cancelled or `sleep` throws, as often as who is looking and what the agent is doing call for.
    /// These `events` are what keeps the session awake in the host, which closes an idle one that no request names for ten minutes: the wait must stay well under half of that.
    public func run() async {
        running = true
        defer { running = false }
        watchViewing()
        repeat { await poll() } while await rest()
    }

    @ObservationIgnored var running = false

    /// Waits until the next round is due; false when the task was cancelled.
    func rest() async -> Bool {
        let working = busy || streaming.isEmpty == false || preparation == .running
        let seconds = conversationWait(state: viewing.state, turnRunning: working, failures: failures) ?? conversationPause
        do {
            if let sleep {
                try await sleep(.seconds(seconds))
            } else {
                // the nap waits on a task of its own, which does not hear a cancellation: cutting it short ends the wait with the task
                await withTaskCancellationHandler { await nap.sleep(seconds: seconds) } onCancel: { nap.wake() }
                try Task.checkCancellation()
            }
        } catch { return false }
        return true
    }

    /// A change of who is looking (the window shows, hides, the Mac sleeps) cuts the wait short, so the model asks at the new pace at once.
    private func watchViewing() {
        guard running else { return }
        withObservationTracking {
            _ = viewing.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.running else { return }
                self.nap.wake()
                self.watchViewing()
            }
        }
    }

    /// Whether a round is under way, and whether another was asked for meanwhile.
    @ObservationIgnored private var polling = false
    @ObservationIgnored var again = false

    /// One round: reads pages until one is not full, then rebuilds the feed when something changed. A round asked for while one is under
    /// way (an action's, or the one `deliver` asks from inside a round) is not a second reader of the same cursor: the one under way goes
    /// round once more when it ends.
    public func poll() async {
        guard polling == false else {
            again = true
            return
        }
        polling = true
        defer { polling = false }
        repeat {
            again = false
            await round()
        } while again
    }
}
