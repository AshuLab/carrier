import CarrierCore
import SwiftUI

/// What an open session shows under its header: messages in bubbles, notes and errors as plain lines, each tool call as a card.
/// A lazy stack inside the epic's scroll view, so only the rows on screen are built.
struct TranscriptView: View {
    let content: TranscriptBody

    var body: some View {
        switch content {
        case .items(let items) where items.isEmpty:
            Text("No activity yet").font(.callout).foregroundStyle(.secondary).padding(12)
        case .items(let items):
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(items) { TranscriptItemView(item: $0) }
            }
            .padding(.horizontal, 12).padding(.bottom, 12)
        case .tail(let lines):
            Text(lines.isEmpty ? "No output yet" : lines.joined(separator: "\n"))
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
    }
}

struct TranscriptItemView: View {
    let item: TranscriptItem

    var body: some View {
        switch item {
        case .message(_, let text):
            Text(text).textSelection(.enabled).lineSpacing(2)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
        case .note(_, let text):
            Text(text).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        case .error(_, let text):
            Text(text).font(.callout).foregroundStyle(.red).textSelection(.enabled)
        case .tool(_, let card):
            ToolCardView(card: card)
        }
    }
}

struct ToolCardView: View {
    let card: TranscriptCard

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: card.kind.icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(RoundedRectangle(cornerRadius: 6).fill(color))
            Text(card.tool).fontWeight(.semibold)
            Text(card.arg).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if card.summary.isEmpty == false { Text(card.summary).foregroundStyle(.secondary).lineLimit(1) }
            if let duration = card.duration { Text(duration).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
            status
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
    }

    @ViewBuilder private var status: some View {
        if let icon = card.status.icon {
            Image(systemName: icon).foregroundStyle(card.status == .error ? Color.red : .green)
        } else {
            ProgressView().controlSize(.mini)
        }
    }

    private var color: Color {
        switch card.kind {
        case .read, .search: Color(red: 0.56, green: 0.36, blue: 0.85)
        case .edit: .blue
        case .shell, .other: Color(white: 0.43)
        }
    }
}
