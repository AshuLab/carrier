import CarrierCore
import SwiftUI

/// The Sessions row and, while `open`, the sessions under it in the chosen order (or "No sessions yet"). Rows of the sidebar's
/// list: the row and each session are tagged with a `Selection`; the buttons in them do not select. The magnifier opens a search
/// field under the row.
struct SessionsRows: View {
    let sessions: Sessions
    /// The order, shared with the Sessions home and remembered by the model.
    @Binding var sort: SessionSort
    @Binding var open: Bool
    /// The last ⌘F: when it asks for Sessions, the search field opens and takes the keyboard.
    let searchRequest: SearchRequest?
    let newSession: () -> Void
    @State private var sortOpen = false
    /// The search field's text while it is open, nil while it is closed; not remembered between launches.
    @State private var query: String?
    @FocusState private var searching: Bool

    private func openSearch() {
        open = true
        if query == nil { query = "" }
        searching = true
    }

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
                // folded, the row says how many sessions wait for the person
                if open == false, let label = sessions.waitingLabel {
                    Text("\(sessions.waiting)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.black)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange))
                        .accessibilityLabel(label)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { open = true })
            .help("Sessions (⌘2)")
            IconButton(icon: "magnifyingglass", name: "Search sessions", shortcut: "⌘F", pressed: query != nil) {
                if query == nil { openSearch() } else { query = nil }
            }
            IconButton(icon: "ellipsis", name: "Sort sessions") { sortOpen.toggle() }
                .popover(isPresented: $sortOpen, arrowEdge: .bottom) {
                    ChoiceMenu(
                        title: "Sort sessions", options: SessionSort.allCases.map { ($0.title, $0) },
                        selection: $sort, close: { sortOpen = false }
                    )
                }
            IconButton(icon: "plus", name: "New session", enabled: sessions.canStart, why: sessions.cannotStartReason, action: newSession)
        }
        .tag(Selection.sessions)
        // the field is only drawn while unfolded, so a query must not outlive it: the magnifier would look pressed with no field
        .onChange(of: open) { if open == false { query = nil } }
        .onChange(of: searchRequest) { if searchRequest?.section == .sessions { openSearch() } }
        if open {
            if let text = Binding($query) {
                TextField("Search sessions", text: text)
                    .textFieldStyle(.roundedBorder)
                    .focused($searching)
                    .onKeyPress(.escape) {
                        query = nil
                        return .handled
                    }
                    .selectionDisabled()
            }
            let searched = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            let groups = sessionGroups(sessions.rows, by: sort, query: query ?? "", now: Date(), calendar: .current)
            if searched {
                let found = groups.flatMap(\.rows)
                Text(found.isEmpty ? "No sessions match" : found.count == 1 ? "1 result" : "\(found.count) results")
                    .font(.caption).foregroundStyle(.secondary).selectionDisabled()
                ForEach(found, id: \.id) { SessionRowView(row: $0, showsWorkspace: true).tag(Selection.session(id: $0.id)) }
            } else {
                if groups.isEmpty {
                    Text("No sessions yet").foregroundStyle(.secondary).selectionDisabled()
                }
                ForEach(groups, id: \.title) { group in
                    if sort == .workspace {
                        WorkspaceHeader(title: group.title, cannotStartReason: sessions.cannotStartReason)
                    } else {
                        Text(group.title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1).selectionDisabled()
                    }
                    ForEach(group.rows, id: \.id) { SessionRowView(row: $0, showsWorkspace: sort != .workspace).tag(Selection.session(id: $0.id)) }
                }
            }
        }
    }
}

private extension SessionSort {
    var title: String {
        switch self {
        case .workspace: "By workspace"
        case .age: "By age"
        case .status: "By status"
        }
    }
}

/// A workspace's name, with a + that appears on hover.
private struct WorkspaceHeader: View {
    let title: String
    let cannotStartReason: String?
    @State private var hovered = false

    var body: some View {
        HStack {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            IconButton(icon: "plus", name: "New session in \(title)", enabled: cannotStartReason == nil, why: cannotStartReason) {}
                .opacity(hovered ? 1 : 0)
        }
        .onHover { hovered = $0 }
        .selectionDisabled()
    }
}

private struct SessionRowView: View {
    let row: SessionRow
    /// Outside the workspace order the group is not the workspace, so the second line says it.
    let showsWorkspace: Bool
    private static let spokenAge: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            SessionGlyph(state: row.state)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
                Text(showsWorkspace ? "\(row.workspace) · \(row.agent)" : row.agent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if row.archived {
                Text("Archived").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().strokeBorder(Color.secondary.opacity(0.5)))
            }
            // "5m" reads aloud as "5 m": say it in words
            Text(sessionAge(row.updatedAt, now: Date())).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                .accessibilityLabel(Self.spokenAge.localizedString(for: min(row.updatedAt, Date()), relativeTo: Date()))
        }
        .opacity(row.archived ? 0.55 : 1)
        .padding(.vertical, 2)
        .contextMenu { SessionMenuItems(row: row) }
        .help(row.title)
    }
}

/// A spinner while working, an orange mark while it waits for the person, a hollow circle when idle and a green check when done.
struct SessionGlyph: View {
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
