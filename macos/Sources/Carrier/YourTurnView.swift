import AppKit
import CarrierCore
import SwiftUI

/// The Overview's Your turn section; a thin mapping of `yourTurn(_:)`. Clicking a row selects the epic.
struct YourTurnView: View {
    let snapshot: PanelSnapshot
    @Binding var selection: Selection

    var body: some View {
        let items = yourTurn(snapshot)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Your turn").font(.headline)
                if items.isEmpty == false { Text("\(items.count) \(items.count == 1 ? "item" : "items")").foregroundStyle(.secondary) }
            }
            if items.isEmpty {
                EmptyStateView(state: .nothingNeedsYou).frame(height: 170)
            } else {
                ForEach(items.indices, id: \.self) { row(items[$0]) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }

    private func row(_ item: YourTurnItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == .ready ? "checkmark" : "exclamationmark")
                .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(item.kind == .ready ? Color.blue : Color.orange))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).fontWeight(.semibold)
                // wraps to two lines instead of being cut when the buttons need room
                Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            OpenLink(title: "Open issue", url: item.issueLink)
            OpenLink(title: "Open PR", url: item.prLink)
        }
        .contentShape(Rectangle())
        .onTapGesture { if let target = item.selection { selection = target } }
    }
}

/// Opens a web link in the default browser; absent when there is none.
private struct OpenLink: View {
    let title: String
    let url: URL?

    var body: some View {
        if let url {
            Button(title) { NSWorkspace.shared.open(url) }.buttonStyle(.glass).controlSize(.small)
        }
    }
}
