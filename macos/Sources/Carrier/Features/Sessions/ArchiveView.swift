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
        VStack(alignment: .leading, spacing: Tokens.Space.none) {
            if let empty = page.emptyState {
                EmptyStateView(state: empty, action: empty == .noSessionsMatch ? ("Clear search", { query = nil }) : nil).inPageScroll()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Tokens.Space.hair) {
                        ForEach(page.groups, id: \.title) { group in
                            if searched == false { groupHeader(group) }
                            ForEach(group.rows, id: \.id) { row in
                                ArchiveRow(row: row, note: page.notes[row.id], open: { select(row.id) }, resume: { resume(row) }, delete: { delete(row) })
                            }
                        }
                    }
                    .padding(.horizontal, Tokens.Space.md).padding(.vertical, Tokens.Space.sm)
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
            HStack(spacing: Tokens.Space.none) {
                searchHalf
                ToolbarPillButton(title: "Filter", icon: .filter) { sortOpen.toggle() }
                    .popover(isPresented: $sortOpen, arrowEdge: .bottom) { sortPopover }
            }
            .glassEffect(.regular, in: .capsule)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            ToolbarPillButton(title: "Clear sessions…", icon: .trash, action: clear)
                .glassEffect(.regular, in: .capsule)
                .padding(.trailing, Tokens.Space.snug)
                .disabled(canClear == false)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    @ViewBuilder private var searchHalf: some View {
        ToolbarSearchField(query: $query, placeholder: "Search archived sessions", focused: $searching)
    }

    private var sortPopover: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("Sort by").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(ArchiveSort.allCases, id: \.self) { option in
                Button {
                    sort = option
                    sortOpen = false
                } label: {
                    HStack {
                        Text(option.title)
                        Spacer(minLength: 0)
                        if sort == option { Glyph(.check) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityAddTraits(sort == option ? .isSelected : [])
            }
        }
        .padding(Tokens.Space.md).frame(width: 200)
    }

    private func groupHeader(_ group: SessionGroup) -> some View {
        HStack(spacing: Tokens.Space.tight) {
            Text(group.title).font(.callout.weight(.semibold))
            Text(group.rows.count == 1 ? "1 session" : "\(group.rows.count) sessions").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, Tokens.Space.sm).padding(.top, Tokens.Space.roomy).padding(.bottom, Tokens.Space.xs)
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
        HStack(alignment: .top, spacing: Tokens.Space.md) {
            ProjectIcon(base: row.base, name: row.workspace, colorKey: projectColorKey(row.base)).environment(\.rowActive, active)
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                HStack(spacing: Tokens.Space.tight) {
                    Text(row.title).font(.scaled(13, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    RowTag(text: row.workspace)
                }
                if let note { Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
                meta
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: Tokens.Space.tight) {
                Text(timeText(row.updatedAt, now: Date(), format: timeChanges.format)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel(spokenAge(row.updatedAt, now: Date()))
                ProviderMarks(names: row.providers)
            }
            .opacity(active ? 0 : 1)
        }
        // faded out, not removed or made untouchable, so they stay in the keyboard's and VoiceOver's reach
        .overlay(alignment: .trailing) {
            HStack(spacing: Tokens.Space.xs) {
                RowIconButton(symbol: .fileText, title: "Open", action: open)
                RowIconButton(symbol: .undo, title: "Resume", action: resume)
                RowIconButton(symbol: .trash, title: "Delete", action: delete)
            }
            .focused($actionsFocused)
            .opacity(active ? 1 : 0)
        }
        .animation(.easeInOut(duration: 0.15), value: active)
        .padding(.horizontal, Tokens.Space.snug).padding(.vertical, Tokens.Space.sm)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(active ? Color.primary.opacity(0.07) : .clear))
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
        HStack(spacing: Tokens.Space.tight) {
            Label(row.branch ?? "Base folder", icon: row.branch == nil ? .folder : .gitBranch)
                .labelStyle(.titleAndIcon).lineLimit(1).truncationMode(.middle)
            if row.turns > 0 { Text("·"); Text(row.turns == 1 ? "1 turn" : "\(row.turns) turns") }
            if let model = TurnSummary(model: row.model).shortModel { Text("·"); Text(model) }
        }
        .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
    }
}
