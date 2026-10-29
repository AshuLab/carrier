import CarrierCore
import SwiftUI

/// An open session's conversation: the feed of the person's messages and the agent's, newest at the bottom. It polls the chat host
/// while it is on screen: the task ends, and with it the polling, when the person selects something else.
struct ConversationView: View {
    /// The smoke check reports how the feed is laid out from these.
    static let layout = "lazy stack, pages of \(ConversationModel.page) events, polled every \(ConversationModel.intervalMilliseconds) ms"
    /// The feed's column, as in the mockups (chat-ui-conv2.html).
    private static let column: CGFloat = 760

    @State private var model: ConversationModel
    @Environment(SessionActions.self) private var actions
    /// The tool groups and calls the person opened, by id; here and not in each row, which the lazy stack may recreate.
    @State private var opened: Set<String> = []
    @FocusState private var boxFocused: Bool
    /// Whether rows are animated in: not the ones the first answer brings, which are the history.
    @State private var animatesRows = false

    /// Where a first message that failed to send is handed over, by the session the draft opened.
    private let draft: NewSessionModel?

    init(sessionId: String, draft: NewSessionModel? = nil) {
        self.draft = draft
        _model = State(initialValue: ConversationModel(host: SocketChatHost(), sessionId: sessionId))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if model.loaded {
                    let open = openOutcome(model.rows)
                    ForEach(model.rows) { row in
                        FeedRowView(
                            row: row, opened: $opened, agent: model.agent, offersWayOut: row.id == open,
                            continueTurn: { Task { await model.continueTurn() } }, retry: { Task { await model.retry() } },
                            answer: { approval, choice in Task { await model.answer(approval, choice: choice) } }
                        )
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                    // between Enter and the first words of the answer
                    if model.busy, case .user = model.rows.last {
                        ThinkingRow().transition(.opacity)
                    }
                } else if model.failure == nil {
                    LoadingRow()
                }
                if let failure = model.failure { Text(failure).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            }
            .padding(.horizontal, 40).padding(.vertical, 16)
            .frame(maxWidth: Self.column, alignment: .leading)
            .frame(maxWidth: .infinity)
            .animation(animatesRows ? .smooth(duration: 0.28) : nil, value: model.rows.count)
        }
        // the end of the conversation is what shows, and stays in view as it grows; a short one starts at the top
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.top, for: .alignment)
        .onChange(of: model.loaded) { _, loaded in
            guard loaded else { return }
            Task { try? await Task.sleep(for: .milliseconds(400)); animatesRows = true }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { if model.archived { archivedBox } else { box } }
        .task {
            if let failed = draft?.takeFailure(of: model.sessionId) { model.showRefusal(of: failed.text, failed.reason) }
            await model.run()
        }
    }

    /// An archived session is read only: a notice with Resume, which takes it out of the archive (the next poll gives the box back).
    private var archivedBox: some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox").foregroundStyle(.secondary)
            Text(archivedSessionNotice).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Resume") { Task { if let refusal = await actions.restore(model.sessionId) { tell(refusal) } } }
                .buttonStyle(.glassProminent).buttonBorderShape(.capsule)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.secondary.opacity(0.10)))
        .padding(.horizontal, 40).padding(.vertical, 12)
        .frame(maxWidth: Self.column).frame(maxWidth: .infinity)
    }

    /// The message box, the same as the draft's (chat-ui-conv.html, section 3): the queued message above it, then the box with the
    /// session's provider and the options the provider lists as selects, and what the host refused under it.
    private var box: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.loaded, model.live == false {
                Text(closedSessionNotice).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let queued = model.queued {
                HStack(spacing: 8) {
                    Image(systemName: "clock").foregroundStyle(.secondary)
                    Text(queued).lineLimit(2).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Text("Sends when the agent finishes").font(.subheadline).foregroundStyle(.secondary)
                    Button { model.cancelQueued() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Cancel the queued message").accessibilityLabel("Cancel the queued message")
                }
                .font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            MessageBox(
                text: $model.draft, placeholder: "Message the agent", minLines: 2,
                canSend: model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, busy: model.busy,
                focus: $boxFocused, send: { Task { await model.submit() } }, stop: { Task { await model.stop() } }
            ) {
                if model.agent.isEmpty == false {
                    ComposerSelect(title: "Provider", icon: "sparkle", selected: model.agent, showsValue: true, locked: true, choices: [SelectChoice(id: model.agent, label: model.agent)])
                }
                ForEach(optionRows(model.options)) { row in
                    ComposerSelect(
                        title: row.label, icon: optionIcon(row.id), selected: row.choices.first { $0.ticked }?.id, showsValue: true,
                        choices: row.choices.map { SelectChoice(id: $0.id, label: $0.label) },
                        choose: { value in Task { await model.setOption(row.id, value) } }
                    )
                }
            }
            if let refusal = model.optionRefusal { Text(refusal).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            if let refusal = model.refusal {
                if model.refusedText == nil {
                    Text(refusal).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                } else {
                    BannerView(banner: refusalBanner(agent: model.agent, reason: refusal), copyDetails: false, retry: { Task { await model.retry() } })
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: model.queued)
        .padding(.horizontal, 40).padding(.vertical, 12)
        .frame(maxWidth: Self.column).frame(maxWidth: .infinity)
        .onAppear { boxFocused = true }
    }

    /// The icon of an option's select: what it is about, by the id the providers use.
    private func optionIcon(_ id: String) -> String {
        switch id {
        case "model": "cpu"
        case "effort": "brain"
        case "permissionMode", "approvalPolicy", "sandbox": "lock.shield"
        default: "slider.horizontal.3"
        }
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
    @Binding var opened: Set<String>
    let agent: String
    /// Whether this is the stopped or failed turn the person can still act on: Continue and Try again show only there.
    let offersWayOut: Bool
    let continueTurn: () -> Void
    let retry: () -> Void
    let answer: (String, String) -> Void

    var body: some View {
        switch row {
        case .user(_, let text):
            Text(text).textSelection(.enabled)
                .padding(.horizontal, 13).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.14)))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 120)
        case .agent(_, let text, let inProgress):
            VStack(alignment: .leading, spacing: 5) {
                MarkdownView(text: text)
                if inProgress { Text("▍").foregroundStyle(.secondary) }
            }
        case .turnEnd(_, let text):
            Text(text).font(.system(size: 11)).foregroundStyle(.tertiary).textSelection(.enabled)
        case .tools(let id, let group):
            ChatToolGroupView(id: id, group: group, opened: $opened)
        case .approval(_, let card):
            ApprovalCardView(card: card, answer: answer)
        case .decided(_, let text, let allow):
            ApprovalDecidedView(text: text, allow: allow)
        case .line(_, let text):
            Text(text).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
        case .error(_, let text):
            BannerView(banner: failedTurnBanner(agent: agent, error: text), copyDetails: true, retry: offersWayOut ? retry : nil)
        case .stopped:
            HStack(spacing: 6) {
                Text("\u{25A0} You stopped this turn").foregroundStyle(.secondary)
                if offersWayOut { Button("Continue", action: continueTurn).buttonStyle(.link) }
            }
            .font(.system(size: 12))
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
                Text(banner.detail).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                if let hint = banner.hint { Text(hint).font(.system(size: 12)).foregroundStyle(.secondary) }
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
        .font(.callout)
        .padding(.horizontal, 13).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(tint.opacity(0.11)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tint.opacity(0.5), lineWidth: 1))
    }
}

/// A fenced block of an agent's message: its language, a Copy button that puts the code on the pasteboard, and the code, which
/// scrolls sideways instead of wrapping.
struct CodeBlockView: View {
    let language: String?
    let code: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                CopyButton(text: code, help: "Copy the code")
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 0.5)
            ScrollView(.horizontal) {
                Text(code).font(.system(size: 11.5, design: .monospaced)).textSelection(.enabled).padding(12)
            }
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
        .font(.callout).foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
