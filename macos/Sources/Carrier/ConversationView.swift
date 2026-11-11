import CarrierCore
import SwiftUI

/// An open session's conversation: the feed of the person's messages and the agent's, newest at the bottom. It polls the chat host
/// while it is on screen: the task ends, and with it the polling, when the person selects something else.
struct ConversationView: View {
    /// The smoke check reports how the feed is laid out from these.
    static let layout = "lazy stack, pages of \(ConversationModel.page) events, polled every \(ConversationModel.intervalMilliseconds) ms"
    @State private var model: ConversationModel
    @Environment(SessionActions.self) private var actions
    /// The tool groups and calls the person flipped from how the tools show, by id; here and not in each row, which the lazy stack may recreate.
    @State private var flipped: Set<String> = []
    @State private var boxFocused = false
    /// Whether rows are animated in: not the ones the first answer brings, which are the history.
    @State private var animatesRows = false
    /// Whether the feed has been taken to its end after it loaded: until then it is not drawn, so the way down is not seen.
    @State private var positioned = false
    @AppStorage(AppPreferences.toolOutputKey) private var toolOutput = AppPreferences.defaultToolOutput
    @AppStorage(AppPreferences.densityKey) private var density = AppPreferences.defaultDensity
    @AppStorage(AppPreferences.showsReasoningKey) private var showsReasoning = AppPreferences.defaultShowsReasoning
    @AppStorage(AppPreferences.followsOutputKey) private var followsOutput = AppPreferences.defaultFollowsOutput
    @State private var position = ScrollPosition()
    /// The rows on screen, which tell the timeline which turns they are in.
    @State private var visibleRows: Set<String> = []
    /// One tick per turn for the timeline at the edge; see `onChange` of the feed's row count.
    @State private var markers: [TurnMarker] = []
    /// The feed's column; medium is the one of the mockups (chat-ui-conv2.html).
    @AppStorage(AppPreferences.messageWidthKey) private var messageWidth = AppPreferences.defaultMessageWidth
    @AppStorage(AppPreferences.whileWorkingKey) private var whileWorking = AppPreferences.defaultWhileWorking

    /// Where the first message of the session the draft opened is handed over, so it shows while the session is prepared.
    private let draft: NewSessionModel?
    /// Told with the plan the host gave back when a preparation was cancelled, so the app can show the draft with it.
    private let cancelled: (SessionPlan) -> Void
    /// The last shortcut that asked something of the conversation (focus the box, the latest message, fold the tools, copy the answer).
    private let request: ConversationRequest?

    init(sessionId: String, draft: NewSessionModel? = nil, request: ConversationRequest? = nil, cancelled: @escaping (SessionPlan) -> Void = { _ in }) {
        self.draft = draft
        self.request = request
        self.cancelled = cancelled
        _model = State(initialValue: ConversationModel(host: SocketChatHost(), sessionId: sessionId, memory: .userDefaults))
    }

    var body: some View {
        // derived once per evaluation: the feed the tools' mode and the reasoning setting leave, with the closing lines folded into their messages
        let shown = foldingClosingLines(visibleFeed(model.rows, mode: toolOutput, showsReasoning: showsReasoning))
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: density.messageGap) {
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
                        Label(note.text, systemImage: note.failed ? "exclamationmark.triangle.fill" : "eye.fill").font(.scaled(11)).foregroundStyle(note.failed ? .orange : .secondary).textSelection(.enabled)
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
                            row: row, time: model.times[row.id], summary: closing[row.id], pinned: row.id == pinnedAnswer, flipped: $flipped, agent: model.agent, commands: model.shownCommands, offersWayOut: row.id == open,
                            work: WorkState(live: row.id == working, waiting: waiting, since: began),
                            continueTurn: { Task { await model.continueTurn() } }, retry: { Task { await model.retry() } },
                            answer: { approval, choice in Task { await model.answer(approval, choice: choice) } }
                        )
                        .transition(Self.transition(of: row))
                    }
                    // between Enter and the first thing the agent does: the card of its work already, so the first step takes its place unseen
                    if model.busy, model.steps.isEmpty, case .user = feed.last {
                        ChatToolGroupView(id: "thinking", group: ToolGroup(calls: []), live: true, waiting: waiting, since: began, flipped: $flipped).transition(.identity)
                    }
                } else if model.failure == nil {
                    LoadingRow()
                }
                if let failure = model.failure { Text(failure).font(.scaled(12)).foregroundStyle(.red).textSelection(.enabled) }
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
        .scrollPosition($position)
        .onScrollGeometryChange(for: Bool.self) { $0.visibleRect.maxY >= $0.contentSize.height - 24 } action: { _, atEnd in model.atEnd = atEnd }
        .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.5) { ids in visibleRows = Set(ids) }
        .overlay(alignment: .leading) {
            if markers.count >= timelineMinimumTurns {
                ConversationTimeline(markers: markers, current: turns(showing: visibleRows, in: markers)) { id in
                    withAnimation(.smooth(duration: 0.3)) { position.scrollTo(id: id, anchor: .top) }
                }
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
            if positioned { withAnimation(.smooth(duration: 0.25)) { position.scrollTo(edge: .bottom) } } else { position.scrollTo(edge: .bottom) }
        }
        .onChange(of: request) { if let request { perform(request.action) } }
        .onChange(of: model.loaded) { _, loaded in
            guard loaded else { return }
            Task {
                // opening a session shows its end, not the way there: the rows are measured as they come, so the end moves while they do;
                // it is gone to again, out of sight, until they have settled, and the feed fades in there
                for delay in [0, 90, 220] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    withTransaction(Transaction(animation: nil)) { position.scrollTo(edge: .bottom) }
                }
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.easeOut(duration: 0.18)) { positioned = true }
                try? await Task.sleep(for: .milliseconds(400))
                animatesRows = true
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { if model.archived { archivedBox } else { box } }
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
        case .stopAgent: if model.busy { Task { await model.stop() } }
        case .jumpToLatest: position.scrollTo(edge: .bottom)
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
        HStack(spacing: 12) {
            Image(systemName: "archivebox").foregroundStyle(.secondary)
            Text(archivedSessionNotice).font(.scaled(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Resume") { Task { if let refusal = await actions.restore(model.sessionId) { tell(refusal) } } }
                .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.secondary.opacity(0.10)))
        .padding(.horizontal, 40).padding(.vertical, 12)
        .frame(maxWidth: messageWidth.points).frame(maxWidth: .infinity)
    }

    /// The message box, the same as the draft's (chat-ui-conv.html, section 3): the queued message above it, then the box with the
    /// session's provider and the options the provider lists in one button, and what the host refused under it.
    private var box: some View {
        VStack(alignment: .leading, spacing: 8) {
            let approvals = pendingApprovals(model.rows)
            if let card = approvals.first {
                Group {
                    if card.questions.isEmpty {
                        ApprovalCardView(card: card, behind: approvals.count - 1) { approval, choice in Task { await model.answer(approval, choice: choice) } }
                    } else {
                        QuestionCardView(card: card, behind: approvals.count - 1) { approval, choice, answers in Task { await model.answer(approval, choice: choice, answers: answers) } }
                            .id(card.approvalId)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if model.asleep { ClosedSessionNotice(chosen: model.wakeOptions.isEmpty == false).transition(.opacity) }
            if let queued = model.queued {
                QueuedMessageCard(
                    text: queued, interrupts: whileWorking == .interrupt,
                    edit: { model.editQueued() }, sendNow: { Task { await model.sendQueuedNow() } }, cancel: { model.cancelQueued() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            MessageBox(
                text: $model.draft, placeholder: "Message the agent", minLines: 2,
                canSend: model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, busy: model.busy,
                focus: $boxFocused, commands: model.shownCommands, send: { Task { await model.submit(whileWorking: whileWorking) } }, stop: { Task { await model.stop() } }
            ) {
                ComposerMenuButton(
                    providers: model.agent.isEmpty ? [] : [ProviderTab(name: model.agent, icon: model.agent)], agent: model.agent, locked: true,
                    options: model.shownOptions,
                    // a closed session lists what it offered when it last ran, and what is chosen waits for the message that wakes it; one the app
                    // never saw running lists nothing, and the panel says so
                    emptyNote: model.asleep ? "The provider lists these once the session is awake. Send a message to wake it up." : "Reading what the provider offers…",
                    busy: model.busy, chooseAgent: { _ in }, choose: { option, value in Task { await model.setOption(option, value) } }
                )
            }
            if let refusal = model.optionRefusal { Text(refusal).font(.scaled(12)).foregroundStyle(.red).textSelection(.enabled) }
            if let refusal = model.refusal {
                if model.refusedText == nil {
                    Text(refusal).font(.scaled(12)).foregroundStyle(.red).textSelection(.enabled)
                } else {
                    BannerView(banner: refusalBanner(agent: model.agent, reason: refusal), copyDetails: false, retry: { Task { await model.retry() } })
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: model.queued)
        .animation(.smooth(duration: 0.25), value: model.asleep)
        .animation(.smooth(duration: 0.25), value: pendingApprovals(model.rows).first?.approvalId)
        // the window asks the box for its smallest size with no width at all, and a notice that wraps would answer with a word a line:
        // taller than the window (a closed session's notice made it ask for 450 points more than it had)
        .frame(minWidth: 320)
        .padding(.horizontal, 40).padding(.vertical, 12)
        .frame(maxWidth: messageWidth.points).frame(maxWidth: .infinity)
        .onAppear { boxFocused = true }
    }
}

private struct FeedRowView: View {
    let row: FeedRow
    /// When the message was written, in ms; nil for a row that is not a stored message.
    let time: Int?
    /// What the turn that ended on this message says of itself (the model, how long, the tokens), shown on hover.
    let summary: TurnSummary?
    /// Whether the footer stays in view without the pointer: the last answer of the conversation.
    let pinned: Bool
    @Binding var flipped: Set<String>
    let agent: String
    /// What the session lists, to show the commands a message names as pills.
    let commands: [ChatCommand]
    /// Whether this is the stopped or failed turn the person can still act on: Continue and Try again show only there.
    let offersWayOut: Bool
    /// What a run of the agent's work needs to know to draw itself: whether it is the one working now.
    let work: WorkState
    let continueTurn: () -> Void
    let retry: () -> Void
    let answer: (String, String) -> Void
    @AppStorage(AppPreferences.messageTimesKey) private var messageTimes = AppPreferences.defaultMessageTimes
    @State private var hovering = false
    @State private var copied = false
    @State private var overCopy = false

    var body: some View {
        switch row {
        case .user(_, let text):
            // the files that came with it are chips over the bubble, and the bubble is what the person wrote
            let sent = splitAttachments(text)
            VStack(alignment: .trailing, spacing: 3) {
                if sent.paths.isEmpty == false { SentAttachments(paths: sent.paths).padding(.bottom, 3) }
                if sent.text.isEmpty == false {
                    messageText(sent.text, commands: commands).textSelection(.enabled)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .glassEffect(.regular.tint(Color.themeAccent.opacity(0.1)), in: .rect(cornerRadius: 16))
                }
                footer(text, summary: nil, asks: false)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 120)
            .onHover { hovering = $0 }
        case .agent(_, let text, let inProgress):
            VStack(alignment: .leading, spacing: 5) {
                MarkdownView(text: text)
                // the cursor takes the footer's height, so the answer does not grow when it ends and the footer takes its place
                if inProgress { Text("▍").foregroundStyle(.secondary).frame(height: 24, alignment: .leading) }
                if inProgress == false { footer(text, summary: summary, asks: true) }
            }
            .onHover { hovering = $0 }
        case .turnEnd(_, let summary):
            Text(summary.text).font(.scaled(12)).foregroundStyle(.secondary).textSelection(.enabled)
        case .tools(let id, let group):
            ChatToolGroupView(id: id, group: group, live: work.live, waiting: work.waiting, since: work.since, flipped: $flipped)
        case .approval:
            EmptyView() // drawn over the message box, never in the feed (`visibleFeed`)
        case .decided(_, let text, let allow):
            ApprovalDecidedView(text: text, allow: allow)
        case .line(_, let text):
            Text(text).codeFont(12).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
        case .error(_, let text):
            BannerView(banner: failedTurnBanner(agent: agent, error: text), copyDetails: true, retry: offersWayOut ? retry : nil)
        case .stopped:
            HStack(spacing: 6) {
                Text("\u{25A0} You stopped this turn").foregroundStyle(.secondary)
                if offersWayOut { Button("Continue", action: continueTurn).buttonStyle(.link) }
            }
            .font(.scaled(12))
        }
    }
}

extension FeedRowView {
    /// Under a message: the copy button, its time and, for an agent message, what the turn that ended on it says of itself (the model as a
    /// chip, how long, the tokens). The row is the same height with or without them, so showing them moves nothing; they fade in and out.
    fileprivate func footer(_ text: String, summary: TurnSummary?, asks: Bool) -> some View {
        let shown = hovering || pinned || copied
        return HStack(spacing: 10) {
            copyControl(text, asks: asks).opacity(shown ? 1 : 0).allowsHitTesting(shown)
            stamp(shown: shown)
            if let summary { summaryView(summary).opacity(shown ? 1 : 0) }
        }
        .frame(height: 24)
        .animation(.easeInOut(duration: 0.18), value: shown)
    }

    private func summaryView(_ summary: TurnSummary) -> some View {
        let numbers = [summary.duration, summary.context.map { "\(TurnSummary.tokens($0)) context" }, summary.output.map { "\(TurnSummary.tokens($0)) out" }]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 10) {
            if let model = summary.shortModel {
                Text(model).font(.scaled(11, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Color.secondary.opacity(0.14)))
                    .help(summary.model ?? model)
            }
            if numbers.isEmpty == false {
                Text(numbers).font(.scaled(12)).foregroundStyle(Color.secondary.opacity(0.8)).help(breakdown(summary))
            }
        }
    }

    /// What the context is made of, for the tooltip of the numbers.
    private func breakdown(_ summary: TurnSummary) -> String {
        [("New input", summary.input), ("Read from the cache", summary.cacheRead), ("Written to the cache", summary.cacheWrite), ("Output", summary.output)]
            .compactMap { name, count in count.map { "\(name): \(Int($0).formatted())" } }.joined(separator: "\n")
    }

    /// Copies the message as it was written (its Markdown) and says so with a green tick for a moment. An agent message also offers its plain text, with the
    /// Markdown marks taken out, from the menu next to the button.
    @ViewBuilder private func copyControl(_ text: String, asks: Bool) -> some View {
        let label = Image(systemName: copied ? "checkmark" : "doc.on.doc")
            .font(.scaled(12)).foregroundStyle(copied ? Color.green : Color.secondary)
            .frame(width: 26, height: 22)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(overCopy ? 0.16 : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        Group {
            if asks {
                Menu {
                    Button("Copy as Markdown") { copy(text) }
                    Button("Copy as plain text") { copy(plainText(text)) }
                } label: { label } primaryAction: { copy(text) }
                    .menuStyle(.button).menuIndicator(.hidden)
            } else {
                Button { copy(text) } label: { label }
            }
        }
        .buttonStyle(.plain).fixedSize()
        .onHover { overCopy = $0 }
        .help("Copy message").accessibilityLabel("Copy message")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    /// The text with the inline marks (bold, links, code ticks) read and dropped; the line breaks and the code blocks stay as they are.
    private func plainText(_ markdown: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)).map { String($0.characters) } ?? markdown
    }

    @ViewBuilder fileprivate func stamp(shown: Bool) -> some View {
        if let time { MessageTimeLabel(ms: time, mode: messageTimes, hovering: shown) }
    }
}

/// The time a message was written, in the General format. On hover it keeps its place and only fades in, so the rows do not jump.
struct MessageTimeLabel: View {
    let ms: Int
    let mode: MessageTimes
    let hovering: Bool
    private let timeChanges = TimeFormatChanges()

    var body: some View {
        if mode != .never {
            // a relative time ages while the row stays on screen
            TimelineView(.everyMinute) { context in
                Text(timeText(Date(ms: ms), now: context.date)).font(.scaled(12)).monospacedDigit().foregroundStyle(.secondary)
                    .opacity(mode.shows(hovering: hovering) ? 1 : 0)
            }
        }
    }
}

/// A banner of a failed turn or a refused send: red for a failure, orange when the provider is not signed in (chat-ui-conv.html, section 3).
private struct BannerView: View {
    let banner: FailureBanner
    /// Copy details puts the provider's text on the pasteboard; a failed turn has it, a refusal says its reason in full already.
    let copyDetails: Bool
    /// Nil when the turn is no longer the last thing: the banner is then only a record.
    let retry: (() -> Void)?

    private var tint: Color { banner.hint == nil ? .red : .orange }

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title).fontWeight(.semibold)
                Text(banner.detail).font(.scaled(12)).foregroundStyle(.secondary).textSelection(.enabled)
                if let hint = banner.hint { Text(hint).font(.scaled(12)).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let retry { Button("Try again", action: retry) }
            if copyDetails {
                Button("Copy details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(banner.detail, forType: .string)
                }
            }
        }
        .font(.scaled(12))
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(tint.opacity(0.11)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tint.opacity(0.5), lineWidth: 1))
    }
}

/// What a run of the agent's work draws itself from: whether it is the one working now, whether an approval holds it, when the turn began.
private struct WorkState {
    let live: Bool
    let waiting: Bool
    let since: Int?
}

/// The message held while the agent answers, over the message box in the same glass as the work card: what it says and when it goes.
/// Clicking the message puts it back in the box to edit; Send now stops the turn and sends it (not offered when sending already stops
/// the turn, which is what the setting says); the cross drops it.
private struct QueuedMessageCard: View {
    let text: String
    let interrupts: Bool
    let edit: () -> Void
    let sendNow: () -> Void
    let cancel: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "clock").font(.scaled(11, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 26, height: 26).background(Circle().fill(Color.primary.opacity(0.08)))
                .accessibilityHidden(true)
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(interrupts ? "Queued · sends when the agent stops" : "Queued · sends when the agent finishes").font(.scaled(11)).foregroundStyle(.secondary)
                    Text(text).font(.scaled(12.5)).lineLimit(2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to edit").accessibilityHint("Puts it back in the box to edit")
            if interrupts == false {
                Button("Send now", action: sendNow).buttonStyle(HoverTextButtonStyle(tint: .themeAccent)).help("Stop the agent and send it now")
            }
            Button(action: cancel) { Image(systemName: "xmark").font(.scaled(10, weight: .bold)) }
                .buttonStyle(HoverTextButtonStyle(tint: nil)).help("Cancel the queued message").accessibilityLabel("Cancel the queued message")
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        // the glass, tint and fill of the work card, so the cards over the box are one family
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.045)))
        .glassEffect(.regular.tint(scheme == .dark ? Color.black.opacity(0.3) : nil), in: .rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }
}

/// A button that is only its text (or icon) until the pointer is over it, when a pill lights behind it: light enough to sit beside a
/// message without weighing as much as it.
private struct HoverTextButtonStyle: ButtonStyle {
    let tint: Color?
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.scaled(12, weight: .medium))
            .foregroundStyle(tint ?? (hovered ? Color.primary : Color.secondary))
            .padding(.horizontal, 10).frame(minWidth: 26, minHeight: 26)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.16 : hovered ? 0.09 : 0)))
            .contentShape(Capsule())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// A session whose agent is not running: what it means and what a message does, above the box, in the colour of night.
private struct ClosedSessionNotice: View {
    /// Whether the person already chose something that will apply when the session wakes.
    let chosen: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.scaled(14, weight: .medium)).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.indigo.opacity(0.85)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(closedSessionNotice.title).fontWeight(.semibold)
                Text(chosen ? closedSessionNotice.chosen : closedSessionNotice.detail).font(.scaled(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .font(.scaled(12)).padding(12)
        // glass, so the conversation that scrolls under it is blurred and not seen through it
        .glassEffect(.regular.tint(Color.indigo.opacity(0.3)), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
