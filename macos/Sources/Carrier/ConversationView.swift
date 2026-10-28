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

    init(sessionId: String) {
        _model = State(initialValue: ConversationModel(host: SocketChatHost(), sessionId: sessionId))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if model.loaded {
                    ForEach(model.rows) { FeedRowView(row: $0, opened: $opened) }
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
        .task { await model.run() }
    }
}

private struct FeedRowView: View {
    let row: FeedRow
    @Binding var opened: Set<String>

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
            Text(text).font(.callout).foregroundStyle(.red).textSelection(.enabled)
        }
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
