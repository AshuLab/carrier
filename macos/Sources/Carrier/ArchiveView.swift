import CarrierCore
import SwiftUI

/// The centre when the Archive row is selected: the title and count, one glass group with Search and Filter (which only sorts) and,
/// on the right, Clear sessions…; the archived sessions under it. A row shows Open, Resume and Delete on hover
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
            header(page)
            if let empty = page.emptyState {
                EmptyStateView(state: empty, action: empty == .noSessionsMatch ? ("Clear search", { query = nil }) : nil)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(page.groups, id: \.title) { group in
                            if searched == false { groupHeader(group) }
                            ForEach(group.rows, id: \.id) { row in
                                ArchiveRow(row: row, open: { select(row.id) }, resume: { resume(row) }, delete: { delete(row) })
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Takes the session out of the archive and opens it; a refusal is told and the session stays where it was.
    private func resume(_ row: SessionRow) {
        Task { if let refusal = await actions.restore(row.id) { tell(refusal) } else { select(row.id) } }
    }

    private func delete(_ row: SessionRow) {
        Task {
            switch await actions.confirmDelete(row) {
            case .refused(let refusal): tell(refusal)
            case .ask(let question):
                guard ask(question) else { return }
                if let refusal = await actions.delete(row.id) { tell(refusal) }
            }
        }
    }

    /// Deletes every archived session, not only the ones a search shows: the question names how many.
    private func clear() {
        let ids = rows.filter(\.archived).map(\.id)
        Task {
            switch await actions.confirmClear(ids) {
            case .refused(let refusal): tell(refusal)
            case .ask(let question):
                guard ask(question) else { return }
                if let refusal = await actions.clear(ids) { tell(refusal) }
            }
        }
    }

    private func header(_ page: ArchivePage) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Archive").font(.title2.weight(.semibold))
                if page.subtitle.isEmpty == false { Text(page.subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            .fixedSize()
            HStack(spacing: 0) {
                searchHalf
                Divider().frame(height: 16)
                Button { sortOpen.toggle() } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease").padding(.horizontal, 12).padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $sortOpen, arrowEdge: .bottom) { sortPopover }
            }
            .glassEffect(.regular, in: .capsule)
            Spacer(minLength: 0)
            Button("Clear sessions…", action: clear)
                .buttonStyle(.glass).buttonBorderShape(.capsule)
                .disabled(page.canClear == false)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    @ViewBuilder private var searchHalf: some View {
        if let text = Binding($query) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search archived sessions", text: text)
                    .textFieldStyle(.plain)
                    .focused($searching)
                    .onKeyPress(.escape) {
                        query = nil
                        return .handled
                    }
                Button { query = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).help("Close search (Esc)").accessibilityLabel("Close search")
            }
            .padding(.horizontal, 12).padding(.vertical, 6).frame(width: 220)
        } else {
            Button {
                query = ""
                searching = true
            } label: { Label("Search", systemImage: "magnifyingglass").padding(.horizontal, 12).padding(.vertical, 6).contentShape(Rectangle()) }
                .buttonStyle(.plain)
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

private extension ArchiveSort {
    var title: String {
        switch self {
        case .dateArchived: "Date archived"
        case .project: "Project"
        }
    }
}

/// An archived session: title with its workspace, the agent and the age; on hover, Open, Resume and Delete.
private struct ArchiveRow: View {
    let row: SessionRow
    let open: () -> Void
    let resume: () -> Void
    let delete: () -> Void
    @State private var hovered = false
    /// Whether the keyboard is on one of the actions, which shows them as the pointer does.
    @FocusState private var actionsFocused: Bool
    private static let spokenAge: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            // a button, so the keyboard and VoiceOver can open the session like a pointer does
            Button(action: open) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(row.title).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail)
                            Text(row.workspace).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().strokeBorder(Color.secondary.opacity(0.5)))
                        }
                        HStack(spacing: 6) {
                            Text(row.agent)
                            if let branch = row.branch { Text(branch).foregroundStyle(.blue) }
                        }
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // faded out, not removed or made untouchable, so they stay in the keyboard's and VoiceOver's reach
            HStack(spacing: 4) {
                action("Open", "doc.text", open)
                action("Resume", "arrow.uturn.backward", resume)
                action("Delete", "trash", delete)
            }
            .focused($actionsFocused)
            .opacity(hovered || actionsFocused ? 1 : 0)
            Text(sessionAge(row.updatedAt, now: Date())).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityLabel(Self.spokenAge.localizedString(for: min(row.updatedAt, Date()), relativeTo: Date()))
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10).fill(hovered ? Color.primary.opacity(0.07) : .clear))
        .onHover { hovered = $0 }
        .contextMenu { SessionMenuItems(row: row) }
        .help(row.title)
    }

    private func action(_ name: String, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(name, systemImage: icon).labelStyle(.titleAndIcon).font(.caption)
        }
        .buttonStyle(.bordered).controlSize(.small)
    }
}
