import CarrierCore
import SwiftUI

/// The centre when the Archive row is selected: the toolbar carries one glass group with Search and Filter (which only sorts) and, apart,
/// Clear sessions… (the window's title and count are `PanelView`'s), as Sessions does; the archived sessions under it. A row shows Open, Resume and Delete on hover
/// (docs/specs/sessions-in-the-app.md, "Archive"). What it shows is `archivePage`; the search is not remembered, the sort is.
struct ArchiveView: View {
    let rows: [SessionRow]
    @Binding var sort: ArchiveSort
    /// Selects the session's conversation.
    let select: (String) -> Void
    @Environment(SessionActions.self) private var actions
    /// The search field's text while it is open, nil while it is closed.
    @State private var query: String?
    @State private var sortOpen = false
    @FocusState private var searching: Bool

    var body: some View {
        let page = archivePage(rows, by: sort, query: query ?? "")
        let searched = (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        VStack(alignment: .leading, spacing: 0) {
            if let empty = page.emptyState {
                EmptyStateView(state: empty, action: empty == .noSessionsMatch ? ("Clear search", { query = nil }) : nil)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(page.groups, id: \.title) { group in
                            if searched == false { groupHeader(group) }
                            ForEach(group.rows, id: \.id) { row in
                                ArchiveRow(row: row, note: page.notes[row.id], open: { select(row.id) }, resume: { resume(row) }, delete: { delete(row) })
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar { toolbar(canClear: page.canClear) }
    }

    /// Takes the session out of the archive and opens it; a refusal is told and the session stays where it was.
    private func resume(_ row: SessionRow) {
        Task { if let refusal = await actions.restore(row.id) { tell(refusal) } else { select(row.id) } }
    }

    private func delete(_ row: SessionRow) { deleteArchived(row, actions) }

    /// Deletes every archived session, not only the ones a search shows: the question names how many.
    private func clear() {
        let ids = rows.filter(\.archived).map(\.id)
        Task {
            switch await actions.confirmClear(ids) {
            case .refused(let refusal): tell(refusal)
            case .ask(let question):
                guard ask(question) else { return }
                fallthrough
            case .proceed:
                if let refusal = await actions.clear(ids) { tell(refusal) }
            }
        }
    }

    @ToolbarContentBuilder private func toolbar(canClear: Bool) -> some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 0) {
                searchHalf
                ToolbarPillButton(title: "Filter", icon: "line.3.horizontal.decrease") { sortOpen.toggle() }
                    .popover(isPresented: $sortOpen, arrowEdge: .bottom) { sortPopover }
            }
            .glassEffect(.regular, in: .capsule)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            ToolbarPillButton(title: "Clear sessions…", icon: "trash", action: clear)
                .glassEffect(.regular, in: .capsule)
                .padding(.trailing, 10)
                .disabled(canClear == false)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    @ViewBuilder private var searchHalf: some View {
        if let text = Binding($query) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.scaled(11, weight: .medium)).foregroundStyle(.secondary).frame(width: 16, height: 16).accessibilityHidden(true)
                TextField("Search archived sessions", text: text)
                    .textFieldStyle(.plain).font(.scaled(12))
                    .focused($searching)
                    .onKeyPress(.escape) {
                        query = nil
                        return .handled
                    }
                Button { query = nil } label: { Image(systemName: "xmark.circle.fill").font(.scaled(11)).foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Close search (Esc)").accessibilityLabel("Close search")
            }
            .padding(.horizontal, 11).frame(width: 220, height: ToolbarPillButton.height)
        } else {
            ToolbarPillButton(title: "Search", icon: "magnifyingglass") {
                query = ""
                searching = true
            }
        }
    }

    private var sortPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sort by").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(ArchiveSort.allCases, id: \.self) { option in
                Button {
                    sort = option
                    sortOpen = false
                } label: {
                    HStack {
                        Text(option.title)
                        Spacer(minLength: 0)
                        if sort == option { Image(systemName: "checkmark") }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityAddTraits(sort == option ? .isSelected : [])
            }
        }
        .padding(12).frame(width: 200)
    }

    private func groupHeader(_ group: SessionGroup) -> some View {
        HStack(spacing: 6) {
            Text(group.title).font(.callout.weight(.semibold))
            Text(group.rows.count == 1 ? "1 session" : "\(group.rows.count) sessions").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

extension ArchiveSort {
    var title: String {
        switch self {
        case .dateArchived: "Date archived"
        case .project: "Project"
        }
    }
}

/// An archived session, drawn as the Sessions list draws its rows: the project's tile, the title with its workspace, what the clock will do
/// with it (or why it is kept), where it worked, the agent and the age; on hover, Open, Resume and Delete take the place of the age.
private struct ArchiveRow: View {
    private let timeChanges = TimeFormatChanges()
    let row: SessionRow
    /// When the clock deletes the session, or why it is still there (`archiveNote`).
    let note: String?
    let open: () -> Void
    let resume: () -> Void
    let delete: () -> Void
    @State private var hovered = false
    /// Whether the keyboard is on one of the actions, which shows them as the pointer does.
    @FocusState private var actionsFocused: Bool

    var body: some View {
        let active = hovered || actionsFocused
        HStack(alignment: .top, spacing: 12) {
            ProjectIcon(name: row.workspace, colorKey: projectColorKey(row.base), working: false).environment(\.rowActive, active)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.title).font(.scaled(13, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    RowTag(text: row.workspace)
                }
                if let note { Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                meta
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(timeText(row.updatedAt, now: Date())).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel(spokenAge(row.updatedAt, now: Date()))
                ProviderMarks(names: row.providers)
            }
            .opacity(active ? 0 : 1)
        }
        // faded out, not removed or made untouchable, so they stay in the keyboard's and VoiceOver's reach
        .overlay(alignment: .trailing) {
            HStack(spacing: 4) {
                RowIconButton(symbol: "doc.text", title: "Open", action: open)
                RowIconButton(symbol: "arrow.uturn.backward", title: "Resume", action: resume)
                RowIconButton(symbol: "trash", title: "Delete", action: delete)
            }
            .focused($actionsFocused)
            .opacity(active ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.15), value: active)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(active ? Color.primary.opacity(0.07) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hovered = $0 }
        .sessionContextMenu(row)
        .help(row.title)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open", open)
    }

    /// Where it worked, how many turns it took and the model of the last.
    private var meta: some View {
        HStack(spacing: 6) {
            Label(row.branch ?? "Base folder", systemImage: row.branch == nil ? "folder" : "arrow.triangle.branch")
                .labelStyle(.titleAndIcon).lineLimit(1).truncationMode(.middle)
            if row.turns > 0 { Text("·"); Text(row.turns == 1 ? "1 turn" : "\(row.turns) turns") }
            if let model = TurnSummary(model: row.model).shortModel { Text("·"); Text(model) }
        }
        .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
    }
}
