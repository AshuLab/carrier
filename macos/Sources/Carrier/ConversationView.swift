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
    @AppStorage(AppPreferences.toolOutputKey) private var toolOutput = AppPreferences.defaultToolOutput
    @AppStorage(AppPreferences.densityKey) private var density = AppPreferences.defaultDensity
    @AppStorage(AppPreferences.followsOutputKey) private var followsOutput = AppPreferences.defaultFollowsOutput
    @State private var position = ScrollPosition()
    /// The feed's column; medium is the one of the mockups (chat-ui-conv2.html).
    @AppStorage(AppPreferences.messageWidthKey) private var messageWidth = AppPreferences.defaultMessageWidth
    @AppStorage(AppPreferences.whileWorkingKey) private var whileWorking = AppPreferences.defaultWhileWorking

    /// Where the first message of the session the draft opened is handed over, so it shows while the session is prepared.
    private let draft: NewSessionModel?
    /// Told with the plan the host gave back when a preparation was cancelled, so the app can show the draft with it.
    private let cancelled: (SessionPlan) -> Void

    init(sessionId: String, draft: NewSessionModel? = nil, cancelled: @escaping (SessionPlan) -> Void = { _ in }) {
        self.draft = draft
        self.cancelled = cancelled
        _model = State(initialValue: ConversationModel(host: SocketChatHost(), sessionId: sessionId, memory: .userDefaults))
    }

    var body: some View {
        ScrollView {
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
                        .transition(.opacity)
                    }
                    if let note = draft?.watchNotes[model.sessionId] {
                        Label(note.text, systemImage: note.failed ? "exclamationmark.triangle.fill" : "eye.fill").font(.scaled(11)).foregroundStyle(note.failed ? .orange : .secondary).textSelection(.enabled)
                    }
                    let open = openOutcome(model.rows)
                    ForEach(visibleFeed(model.rows, mode: toolOutput)) { row in
                        FeedRowView(
                            row: row, time: model.times[row.id], flipped: $flipped, agent: model.agent, commands: model.shownCommands, offersWayOut: row.id == open,
                            continueTurn: { Task { await model.continueTurn() } }, retry: { Task { await model.retry() } },
                            answer: { approval, choice in Task { await model.answer(approval, choice: choice) } }
                        )
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                    // between Enter and the first words of the answer
                    if model.busy, model.steps.isEmpty, case .user = model.rows.last {
                        ThinkingRow().transition(.opacity)
                    }
                } else if model.failure == nil {
                    LoadingRow()
                }
                if let failure = model.failure { Text(failure).font(.scaled(12)).foregroundStyle(.red).textSelection(.enabled) }
            }
            .padding(.horizontal, 40).padding(.vertical, 16)
            .frame(maxWidth: messageWidth.points, alignment: .leading)
            .frame(maxWidth: .infinity)
            .animation(animatesRows ? .smooth(duration: 0.28) : nil, value: model.rows.count)
        }
        // the end of the conversation is what shows; it stays in view as it grows only when Follow new output is on (the model says when to scroll)
        .defaultScrollAnchor(followsOutput ? .bottom : nil)
        .defaultScrollAnchor(.top, for: .alignment)
        .scrollPosition($position)
        .onScrollGeometryChange(for: Bool.self) { $0.visibleRect.maxY >= $0.contentSize.height - 24 } action: { _, atEnd in model.atEnd = atEnd }
        .onChange(of: followsOutput, initial: true) { _, follows in model.followsOutput = follows }
        .onChange(of: model.scrolls) { position.scrollTo(edge: .bottom) }
        .onChange(of: model.loaded) { _, loaded in
            guard loaded else { return }
            Task { try? await Task.sleep(for: .milliseconds(400)); animatesRows = true }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { if model.archived { archivedBox } else { box } }
        .font(.scaled(13))
        .task {
            if let first = draft?.takeFirstMessage(of: model.sessionId) { model.show(firstMessage: first) }
            await model.run()
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
    /// session's provider and the options the provider lists as selects, and what the host refused under it.
    private var box: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.loaded, model.live == false { ClosedSessionNotice(chosen: model.wakeOptions.isEmpty == false).transition(.opacity) }
            if let queued = model.queued {
                HStack(spacing: 8) {
                    Image(systemName: "clock").foregroundStyle(.secondary)
                    Text(queued).lineLimit(2).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Text(whileWorking == .interrupt ? "Sends when the agent stops" : "Sends when the agent finishes").font(.scaled(11)).foregroundStyle(.secondary)
                    Button { model.cancelQueued() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Cancel the queued message").accessibilityLabel("Cancel the queued message")
                }
                .font(.scaled(12))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            MessageBox(
                text: $model.draft, placeholder: "Message the agent", minLines: 2,
                canSend: model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, busy: model.busy,
                focus: $boxFocused, commands: model.shownCommands, halo: true, send: { Task { await model.submit(whileWorking: whileWorking) } }, stop: { Task { await model.stop() } }
            ) {
                if model.agent.isEmpty == false {
                    ComposerSelect(title: "Provider", icon: "sparkle", selected: model.agent, showsValue: true, locked: true, choices: [SelectChoice(id: model.agent, label: model.agent)])
                }
                // a closed session lists what it offered when it last ran, and what is chosen waits for the message that wakes it; one the app
                // never saw running lists nothing, and the selects say so
                if model.loaded, model.live == false, model.shownOptions.isEmpty {
                    ForEach([("Model", "cpu"), ("Reasoning", "brain"), ("Access", "lock.shield")], id: \.0) { title, icon in
                        ComposerSelect(title: title, icon: icon, note: "The provider lists these once the session is awake. Send a message to wake it up.")
                    }
                }
                optionSelects(model.shownOptions) { option, value in Task { await model.setOption(option, value) } }
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
        .animation(.smooth(duration: 0.25), value: model.live)
        // the window asks the box for its smallest size with no width at all, and a notice that wraps would answer with a word a line:
        // taller than the window (a closed session's notice made it ask for 450 points more than it had)
        .frame(minWidth: 320)
        .padding(.horizontal, 40).padding(.vertical, 12)
        .frame(maxWidth: messageWidth.points).frame(maxWidth: .infinity)
        .onAppear { boxFocused = true }
    }
}

/// The title bar's Open button: reveals the session's folder in Finder and copies its path or its branch name; a copy item says
/// "Copied" for a moment.
struct OpenMenu: View {
    let items: [OpenItem]
    @State private var copied: String?

    var body: some View {
        Menu {
            ForEach(items, id: \.title) { item in
                Button(copied == item.title ? "Copied" : item.title) { run(item) }
            }
        } label: {
            Label("Open", systemImage: "folder").labelStyle(.titleAndIcon)
        }
        .help("Open the session's folder")
    }

    private func run(_ item: OpenItem) {
        switch item.action {
        case .reveal(let path):
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        case .copy(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = item.title
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = nil
            }
        }
    }
}

private struct FeedRowView: View {
    let row: FeedRow
    /// When the message was written, in ms; nil for a row that is not a stored message.
    let time: Int?
    @Binding var flipped: Set<String>
    let agent: String
    /// What the session lists, to show the commands a message names as pills.
    let commands: [ChatCommand]
    /// Whether this is the stopped or failed turn the person can still act on: Continue and Try again show only there.
    let offersWayOut: Bool
    let continueTurn: () -> Void
    let retry: () -> Void
    let answer: (String, String) -> Void
    @AppStorage(AppPreferences.messageTimesKey) private var messageTimes = AppPreferences.defaultMessageTimes
    @State private var hovering = false

    var body: some View {
        switch row {
        case .user(_, let text):
            VStack(alignment: .trailing, spacing: 3) {
                messageText(text, commands: commands).textSelection(.enabled)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.14)))
                stamp
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 120)
            .onHover { hovering = $0 }
        case .agent(_, let text, let inProgress):
            VStack(alignment: .leading, spacing: 5) {
                MarkdownView(text: text)
                if inProgress { Text("▍").foregroundStyle(.secondary) }
                stamp
            }
            .onHover { hovering = $0 }
        case .turnEnd(_, let text):
            Text(text).font(.scaled(11)).foregroundStyle(.tertiary).textSelection(.enabled)
        case .tools(let id, let group):
            ChatToolGroupView(id: id, group: group, flipped: $flipped)
        case .approval(_, let card):
            ApprovalCardView(card: card, answer: answer)
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
    @ViewBuilder fileprivate var stamp: some View {
        if let time { MessageTimeLabel(ms: time, mode: messageTimes, hovering: hovering) }
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
                Text(timeText(Date(ms: ms), now: context.date)).font(.scaled(11)).monospacedDigit().foregroundStyle(.tertiary)
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

/// A fenced block of an agent's message: its language, a Copy button that puts the code on the pasteboard, and the code, wrapped or
/// scrolling sideways as the monospace settings say.
struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code").font(.scaled(11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                CopyButton(text: code, help: "Copy the code")
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 0.5)
            MonoLines(lines: code.components(separatedBy: "\n")).codeFont(11.5).textSelection(.enabled).padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// The agent has the message and has not said anything yet: three dots that run.
private struct ThinkingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis").symbolEffect(.variableColor.iterative, options: .repeating)
            Text("Thinking…")
        }
        .font(.scaled(12)).foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// A session whose agent is not running: what it means and what a message does, above the box, in the colour of night.
private struct ClosedSessionNotice: View {
    /// Whether the person already chose something that will apply when the session wakes.
    let chosen: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.zzz.fill")
                .font(.scaled(14, weight: .medium)).foregroundStyle(Color.indigo)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.indigo.opacity(0.2)))
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
