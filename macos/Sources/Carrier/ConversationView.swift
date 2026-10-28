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
    /// The tool groups and calls the person opened, by id; here and not in each row, which the lazy stack may recreate.
    @State private var opened: Set<String> = []
    @FocusState private var boxFocused: Bool

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
                            continueTurn: { Task { await model.continueTurn() } }, retry: { Task { await model.retry() } }
                        )
                    }
                } else if model.failure == nil {
                    LoadingRow()
                }
                if let failure = model.failure { Text(failure).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
            }
            .padding(.horizontal, 40).padding(.vertical, 16)
            .frame(maxWidth: Self.column, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // the end of the conversation is what shows, and stays in view as it grows
        .defaultScrollAnchor(.bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) { box }
        .task {
            if let failed = draft?.takeFailure(of: model.sessionId) { model.showRefusal(of: failed.text, failed.reason) }
            await model.run()
        }
    }

    /// The message box (chat-ui-conv.html, section 3): the queued message above it, the box with its send or Stop button, and what the host refused under it.
    private var box: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.loaded, model.live == false {
                Text(closedSessionNotice).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let queued = model.queued {
                HStack(spacing: 8) {
                    Image(systemName: "clock").foregroundStyle(.secondary)
                    Text(queued).lineLimit(2).textSelection(.enabled)
                    Spacer(minLength: 0)
                    Text("Sends when the agent finishes").font(.system(size: 11)).foregroundStyle(.secondary)
                    Button { model.cancelQueued() } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Cancel the queued message").accessibilityLabel("Cancel the queued message")
                }
                .font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message the agent", text: $model.draft, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...8).focused($boxFocused)
                    // Enter sends and Shift+Enter adds a line
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) {
                            model.draft += "\n"
                        } else {
                            Task { await model.submit() }
                        }
                        return .handled
                    }
                Button {
                    Task { if model.busy { await model.stop() } else { await model.submit() } }
                } label: {
                    Image(systemName: model.busy ? "stop.fill" : "arrow.up")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 26, height: 26).background(Circle().fill(Color.accentColor))
                }
                .buttonStyle(.plain).help(model.busy ? "Stop" : "Send").accessibilityLabel(model.busy ? "Stop" : "Send")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.secondary.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5))
            if let refusal = model.refusal {
                if model.refusedText == nil {
                    Text(refusal).font(.callout).foregroundStyle(.red).textSelection(.enabled)
                } else {
                    BannerView(banner: refusalBanner(agent: model.agent, reason: refusal), copyDetails: false, retry: { Task { await model.retry() } })
                }
            }
        }
        .padding(.horizontal, 40).padding(.vertical, 12)
        .frame(maxWidth: Self.column).frame(maxWidth: .infinity)
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
    @Binding var opened: Set<String>
    let agent: String
    /// Whether this is the stopped or failed turn the person can still act on: Continue and Try again show only there.
    let offersWayOut: Bool
    let continueTurn: () -> Void
    let retry: () -> Void

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
