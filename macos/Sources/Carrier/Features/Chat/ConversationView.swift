import CarrierCore
import SwiftUI

/// An open session's conversation: the feed of the person's messages and the agent's, newest at the bottom. It polls the chat host
/// while it is on screen: the task ends, and with it the polling, when the person selects something else.
struct ConversationView: View {
    /// The smoke check reports how the feed is laid out from these.
    static let layout = "lazy stack, pages of \(ConversationModel.page) events, polled every \(Int(conversationTurnWait * 1000)) ms during a turn, every 2 s idle in front, every 5 s idle behind another app, and about every 30 s while hidden"
    @State private var model: ConversationModel
    @Environment(SessionActions.self) private var actions
    /// The tool groups and calls the person flipped from how the tools show, by id; here and not in each row, which the lazy stack may recreate.
    @State private var flipped: Set<String> = []
    @State private var boxFocused = false
    /// The times the global shortcut asked the box to dictate.
    @State private var dictations = 0
    /// Whether rows are animated in: not the ones the first answer brings, which are the history.
    @State private var animatesRows = false
    /// Whether the feed has been taken to its end after it loaded: until then it is not drawn, so the way down is not seen.
    @State private var positioned = false
    /// The height of the conversation's pane, for what sits over the message box to leave it room (`cardRoom`).
    @State private var paneHeight: CGFloat = 0
    @AppStorage(Preference.chatToolOutput) private var toolOutput
    @AppStorage(Preference.chatMessageSpacing) private var messageSpacing
    @AppStorage(Preference.chatShowReasoning) private var showsReasoning
    @AppStorage(Preference.chatFollowOutput) private var followsOutput
    /// Where the feed is scrolled to and which rows are on screen: in an object of their own, so the feed is not drawn again at each scroll
    /// (it would be at each poll, which scrolls to the end). Only the timeline reads which rows are on screen.
    @State private var scroll = ScrollState()
    /// One tick per turn for the timeline at the edge; see `onChange` of the feed's row count.
    @State private var markers: [TurnMarker] = []
    /// The feed's column; medium is the one of the mockups (chat-ui-conv2.html).
    @AppStorage(Preference.appearanceMessageWidth) private var messageWidth

    /// Where the first message of the session the draft opened is handed over, so it shows while the session is prepared.
    private let draft: NewSessionModel?
    /// Told with the plan the host gave back when a preparation was cancelled, so the app can show the draft with it.
    private let cancelled: (SessionPlan) -> Void
    /// The last shortcut that asked something of the conversation (focus the box, the latest message, fold the tools, copy the answer).
    private let request: ConversationRequest?
    /// The subagent views open over the conversation, the window's (`WindowShell.subagents`): the last one is shown. The header says of it
    /// what `header` is told, which is the window's too.
    @Binding private var subagents: [String]
    @Binding private var header: SubagentHeader?

    init(
        sessionId: String, draft: NewSessionModel? = nil, request: ConversationRequest? = nil, subagents: Binding<[String]> = .constant([]),
        header: Binding<SubagentHeader?> = .constant(nil), cancelled: @escaping (SessionPlan) -> Void = { _ in }
    ) {
        self.draft = draft
        self.request = request
        _subagents = subagents
        _header = header
        self.cancelled = cancelled
        // a model made at every pass over the parent's body is wasted work: the events count them
        Signposts.render.emitEvent("ConversationModel init")
        let model = ConversationModel(host: SocketChatHost(), sessionId: sessionId, memory: .userDefaults)
        model.onQuotaError = { AppUsage.refresher.limitHit() }
        _model = State(initialValue: model)
    }

    var body: some View {
        // the fixture's one session that is not a conversation: all the notices together, to look at them
        (NoticesGalleryView.shows(model.sessionId) ? AnyView(NoticesGalleryView()) : AnyView(conversation))
            // the conversation stays mounted under the subagent view, so Back finds its feed and its place as they were, but it is not drawn: the
            // subagent view replaces it, and nothing of it shows through the window's translucent surfaces; nothing under it takes keys or taps
            .opacity(subagents.isEmpty ? 1 : 0)
            .disabled(subagents.isEmpty == false)
            .accessibilityHidden(subagents.isEmpty == false)
            .overlay {
                if subagents.isEmpty == false {
                    Group {
                        if let work = model.openSubagent {
                            SubagentView(work: work, backToChat: { subagents = [] })
                        } else {
                            LoadingRow()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.themeWindow)
                }
            }
            .environment(\.openSubagent) { subagents.append($0) }
            .environment(\.feedActions, FeedActions(model: model))
            .onChange(of: subagents, initial: true) { before, stack in
                model.show(subagent: stack.last)
                if stack.isEmpty == false {
                    boxFocused = false
                } else if before.isEmpty == false {
                    // back in the conversation the box is where the person goes on, as when the session opened (the box stays mounted under the subagent view, so its `onAppear` does not run again)
                    boxFocused = true
                }
            }
            .onChange(of: model.openSubagent?.header) { _, shown in header = shown }
    }

    private var conversation: some View {
        // derived once per evaluation: the feed the tools' mode and the reasoning setting leave, with the closing lines folded into their messages
        let shown = foldingClosingLines(visibleFeed(model.rows, mode: toolOutput, showsReasoning: showsReasoning))
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: messageSpacing.gap) {
                if model.loaded {
                    if model.steps.isEmpty == false {
                        PreparationStepsView(steps: model.steps, preparation: model.preparation, refusal: model.preparationRefusal, retry: { Task { await model.retryPreparation() } }, cancel: {
                            Task {
                                guard let plan = await model.cancelPreparation() else { return }
                                actions.changed()
                                cancelled(plan)
                            }
                        })
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    }
                    if let note = draft?.watchNotes[model.sessionId] {
                        if note.failed {
                            ProblemLine(text: note.text, font: .scaled(11)).textSelection(.enabled)
                        } else {
                            Label(note.text, icon: .eye).font(.scaled(11)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                    let open = openOutcome(model.rows)
                    let (feed, closing) = shown
                    // the answer the person is looking at keeps its footer in view; the rest show it on hover
                    let pinnedAnswer: String? = {
                        guard let index = feed.lastIndex(where: { if case .agent(_, _, false) = $0 { true } else { false } }) else { return nil }
                        return feed[index...].contains(where: { if case .agent(_, _, true) = $0 { true } else { false } }) ? nil : feed[index].id
                    }()
                    // the run the agent is working in, whether an approval holds it and when the turn began
                    let working = model.busy ? workInProgress(in: feed) : nil
                    let waiting = pendingApprovals(model.rows).isEmpty == false
                    let began = feed.last(where: { if case .user = $0 { true } else { false } }).flatMap { model.times[$0.id] }
                    ForEach(feed) { row in
                        FeedRowView(
                            row: row, time: model.times[row.id], summary: closing[row.id], pinned: row.id == pinnedAnswer, flipped: $flipped, agent: model.agent, commands: model.shownCommands, offersWayOut: row.id == open && model.refusedText == nil,
                            work: WorkState(live: row.id == working, waiting: waiting, since: began)
                        )
                        .equatable()
                        .transition(Self.transition(of: row))
                    }
                    // between Enter and the first thing the agent does: the card of its work already, so the first step takes its place unseen
                    if model.busy, model.steps.isEmpty, case .user = feed.last {
                        ChatToolGroupView(id: "thinking", group: ToolGroup(calls: []), live: true, waiting: waiting, since: began, flipped: $flipped)
                            // gone at once when the answer or the first step takes its place: left to fade with the rows' animation it stays under the answer's first line
                            .transition(.asymmetric(insertion: .identity, removal: .opacity.animation(.linear(duration: 0.01))))
                    }
                } else if model.failure == nil {
                    LoadingRow()
                }
                if let failure = model.failure { ProblemNotice(text: failure, failed: true) }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 40).padding(.vertical, 16)
            .frame(maxWidth: messageWidth.points, alignment: .leading)
            .frame(maxWidth: .infinity)
            // the count and whether the agent is busy (the dots of Thinking come and go with it)
            .animation(animatesRows ? .smooth(duration: 0.28) : nil, value: [shown.rows.count, model.busy ? 1 : 0])
            .opacity(model.loaded == false || positioned ? 1 : 0)
        }
        // the end of the conversation is what shows; it stays in view as it grows only when Follow new output is on (the model says when to scroll)
        .defaultScrollAnchor(followsOutput ? .bottom : nil)
        .defaultScrollAnchor(.top, for: .alignment)
        .modifier(ScrollsWith(scroll: scroll))
        .onScrollGeometryChange(for: Bool.self) { $0.visibleRect.maxY >= $0.contentSize.height - 24 } action: { _, atEnd in model.atEnd = atEnd }
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.5) { ids in
            if scroll.visible != Set(ids) { scroll.visible = Set(ids) }
        }
        .overlay(alignment: .leading) {
            if markers.count >= timelineMinimumTurns {
                TimelineOverlay(markers: markers, scroll: scroll)
                // the toolbar takes the top and the box the bottom: the middle of the window's body, not of the scroll view's frame
                .padding(.top, 160)
                .transition(.opacity)
            }
        }
        .onChange(of: followsOutput, initial: true) { _, follows in model.followsOutput = follows }
        // markers are rebuilt when the feed gains or loses a row, not at each token of the answer in progress nor at each scroll
        .onChange(of: shown.rows.count, initial: true) { markers = turnMarkers(in: shown.rows) }
        // eased like the rows that come in, so the two do not move against each other
        .onChange(of: model.scrolls) {
            // the first load is not eased: it is the end already, seen from the first moment (see `loaded` below)
            if positioned { withAnimation(.smooth(duration: 0.25)) { scroll.position.scrollTo(edge: .bottom) } } else { scroll.position.scrollTo(edge: .bottom) }
        }
        .onChange(of: request) { if let request { perform(request.action) } }
        .onChange(of: model.loaded) { _, loaded in
            guard loaded else { return }
            Task {
                // opening a session shows its end, not the way there: the rows are measured as they come, so the end moves while they do;
                // it is gone to again, out of sight, until they have settled, and the feed fades in there
                for delay in [0, 90, 220] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    withTransaction(Transaction(animation: nil)) { scroll.position.scrollTo(edge: .bottom) }
                }
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeOut(duration: 0.18)) { positioned = true }
                try? await Task.sleep(for: .milliseconds(400))
                animatesRows = true
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { paneHeight = $0 }
        .safeAreaInset(edge: .bottom, spacing: 0) { if model.archived { archivedBox } else { box.environment(\.conversationHeight, paneHeight) } }
        .font(.scaled(13))
        .task {
            if let first = draft?.takeFirstMessage(of: model.sessionId) { model.show(firstMessage: first) }
            await model.run()
        }
    }

    /// A row comes in from the bottom and fades out, except an agent's message and the run of the agent's work: it grows in place as it is written, and the message in
    /// progress is replaced by the finished one (another row id) with nothing to see, so it does not leave and come in again when the
    /// answer ends.
    private static func transition(of row: FeedRow) -> AnyTransition {
        // the card of the agent's work is there from the first moment (see the card drawn while the agent starts), so it comes in with nothing to see
        switch row {
        case .agent, .tools: return .identity
        default: break
        }
        return .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity)
    }

    private func perform(_ action: ConversationAction) {
        switch action {
        case .focusBox: boxFocused = true
        case .dictate: dictations += 1
        case .stopAgent: if model.busy { Task { await model.stop() } }
        case .stopSubagent: Task { await model.stopOpenSubagent() }
        case .jumpToLatest: scroll.position.scrollTo(edge: .bottom)
        case .toggleToolFolds:
            flipped = togglingToolGroups(in: visibleFeed(model.rows, mode: toolOutput, showsReasoning: showsReasoning), flipped: flipped)
        case .copyLastAnswer:
            guard let answer = lastAnswer(in: model.rows) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(answer, forType: .string)
        }
    }

    /// An archived session is read only: a notice with Resume, which takes it out of the archive (the next poll gives the box back).
    private var archivedBox: some View {
        // two lines at most: with no limit this detail made the whole window lay out taller than it is, the notice below its edge
        ArchivedSessionNotice(resume: { Task { if let refusal = await actions.restore(model.sessionId) { tell(refusal) } } })
        .padding(.horizontal, 40).padding(.vertical, 12)
        .frame(maxWidth: messageWidth.points).frame(maxWidth: .infinity)
    }

    /// The message box, the same as the draft's (chat-ui-conv.html, section 3): the queued message above it, then the box with the
    /// session's provider and the options the provider lists in one button, and what the host refused under it.
    private var box: some View { ConversationBox(model: model, boxFocused: $boxFocused, dictations: dictations) }
}
