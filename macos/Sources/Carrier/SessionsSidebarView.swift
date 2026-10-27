import CarrierCore
import SwiftUI

/// The Sessions row and, while `open`, the sessions under it grouped by workspace (or "No sessions yet"). Rows of the sidebar's
/// list: the row and each session are tagged with a `Selection`; the buttons in them do not select. The search and sort buttons
/// do nothing yet (#415, #416).
struct SessionsRows: View {
    let sessions: Sessions
    @Binding var open: Bool

    var body: some View {
        HStack(spacing: 4) {
            Button { open.toggle() } label: {
                Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0)).frame(width: 16, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? "Fold Sessions" : "Unfold Sessions")
            .accessibilityLabel(open ? "Fold Sessions" : "Unfold Sessions")
            // the row selects Sessions and unfolds the list; the gesture sits beside the list's own click, not instead of it
            HStack(spacing: 4) {
                Label("Sessions", systemImage: "bubble.left.and.bubble.right")
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { open = true })
            SessionIconButton(icon: "magnifyingglass", name: "Search sessions") {}
            SessionIconButton(icon: "ellipsis", name: "Sort sessions") {}
            SessionIconButton(icon: "plus", name: "New session", enabled: sessions.canStart, why: Sessions.cannotStartReason) {}
        }
        .tag(Selection.sessions)
        if open {
            let groups = sessionGroups(sessions.rows)
            if groups.isEmpty {
                Text("No sessions yet").foregroundStyle(.secondary).selectionDisabled()
            }
            ForEach(groups, id: \.title) { group in
                WorkspaceHeader(title: group.title, canStart: sessions.canStart)
                ForEach(group.rows, id: \.id) { SessionRowView(row: $0).tag(Selection.session(id: $0.id)) }
            }
        }
    }
}

/// A 22-point plain button with an accessible name and a tooltip; `why` is the tooltip while it is disabled.
private struct SessionIconButton: View {
    let icon: String
    let name: String
    var enabled = true
    var why: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(enabled == false)
        .help(enabled ? name : why ?? name)
        .accessibilityLabel(name)
    }
}

/// A workspace's name, with a + that appears on hover.
private struct WorkspaceHeader: View {
    let title: String
    let canStart: Bool
    @State private var hovered = false

    var body: some View {
        HStack {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            SessionIconButton(icon: "plus", name: "New session in \(title)", enabled: canStart, why: Sessions.cannotStartReason) {}
                .opacity(hovered ? 1 : 0)
        }
        .onHover { hovered = $0 }
        .selectionDisabled()
    }
}

private struct SessionRowView: View {
    let row: SessionRow

    var body: some View {
        HStack(spacing: 10) {
            SessionGlyph(state: row.state)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                Text(row.agent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(sessionAge(row.updatedAt, now: Date())).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 2)
        .help(row.title)
    }
}

/// A spinner while working, an orange mark while it waits for the person, a hollow circle when idle and a green check when done.
private struct SessionGlyph: View {
    let state: SessionState

    var body: some View {
        glyph.frame(width: 20, height: 20).accessibilityLabel(label)
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .working: SpinningRing(diameter: 14, lineWidth: 2, color: .systemBlue)
        case .waiting: Disc(color: .orange, mark: "!")
        case .idle: Circle().strokeBorder(Color.gray, lineWidth: 2).frame(width: 14, height: 14)
        case .done: Disc(color: .green, mark: "✓")
        }
    }

    private var label: String {
        switch state {
        case .working: "Working"
        case .waiting: "Waiting for you"
        case .idle: "Idle"
        case .done: "Done"
        }
    }
}
