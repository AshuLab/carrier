import CarrierCore
import SwiftUI

/// The Terminal section in the sidebar and, while `open`, the standalone terminal instances under it (or its empty block).
/// Mirrors `SessionsRows` in `SessionsSidebarView.swift`.
struct TerminalRows: View {
    let store: CarrierTerminalStore
    @Binding var selection: Selection
    let selected: Bool
    /// Chooses Terminal, which unfolds it.
    let select: () -> Void
    @Binding var open: Bool
    /// The last ⌘F: when it asks for Terminal, the search field opens and takes the keyboard.
    let searchRequest: SearchRequest?
    let newTerminal: () -> Void
    let closeTerminal: (UUID) -> Void
    @State private var query: String?
    @FocusState private var searching: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var terminals: [StandaloneTerminalSummary] { store.standaloneTerminals() }

    private func openSearch() {
        guard terminals.isEmpty == false else { return }
        open = true
        if query == nil { query = "" }
        searching = true
    }

    var body: some View {
        SidebarSectionRow(
            title: "Terminal",
            icon: "terminal",
            selected: selected,
            keepActions: query != nil,
            action: select,
            actions: {
                if terminals.isEmpty == false {
                    Text("\(terminals.count)")
                        .font(SidebarMetrics.detail.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .accessibilityLabel(terminals.count == 1 ? "1 terminal" : "\(terminals.count) terminals")
                }
            },
            hoverActions: {
                IconButton(
                    icon: "magnifyingglass",
                    name: "Search terminals",
                    enabled: terminals.isEmpty == false,
                    why: "No terminals to search",
                    shortcut: "⌘F",
                    pressed: query != nil
                ) {
                    if query == nil { openSearch() } else { query = nil }
                }
                IconButton(icon: "plus", name: "New terminal", action: newTerminal)
            }
        )
        .help("Terminal")
        .onChange(of: open) { if open == false { query = nil } }
        .onChange(of: searchRequest) { if searchRequest?.section == .terminal { openSearch() } }
        if open {
            let shownTerminals = filteredStandaloneTerminals(terminals, query: query ?? "")
            LazyVStack(alignment: .leading, spacing: SidebarMetrics.rowGap) {
                if query != nil {
                    SidebarSearchField(
                        placeholder: "Search terminals",
                        text: Binding(get: { query ?? "" }, set: { query = $0 }),
                        focus: $searching,
                        close: { query = nil }
                    )
                }
                switch SidebarListState(shown: shownTerminals.count, of: terminals.count, query: query ?? "") {
                case .empty:
                    let empty = EmptyState.noTerminals
                    SidebarEmptyBlock(icon: empty.icon, title: empty.title, line: empty.line) {
                        Button("New Terminal Session", action: newTerminal)
                            .help("New terminal session")
                    }
                case .noMatch(let typed):
                    SidebarNoResults(query: typed, clear: { query = "" })
                case .rows:
                    EmptyView()
                }
                ForEach(shownTerminals) { summary in
                    TerminalSidebarRowView(summary: summary) {
                        closeTerminal(summary.id)
                    }
                    .selectableSidebarRow(selected: selection == .terminal(id: summary.id)) {
                        selection = .terminal(id: summary.id)
                    }
                    .onMiddleClick {
                        closeTerminal(summary.id)
                    }
                    .contextMenu {
                        Button {
                            selection = .terminal(id: summary.id)
                        } label: {
                            Label("Open", systemImage: "terminal").labelStyle(.titleAndIcon)
                        }
                        Button {
                            _ = store.openTab(for: .terminal(summary.id), workingDirectory: summary.workingDirectory)
                            selection = .terminal(id: summary.id)
                        } label: {
                            Label("New Tab", systemImage: "plus.rectangle.on.rectangle").labelStyle(.titleAndIcon)
                        }
                        Divider()
                        Button(role: .destructive) {
                            closeTerminal(summary.id)
                        } label: {
                            Label("Close", systemImage: "xmark").labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: shownTerminals.map(\.id))
            .transition(reduceMotion ? .opacity : .reveal)
        }
    }
}

private struct TerminalSidebarRowView: View {
    let summary: StandaloneTerminalSummary
    let close: () -> Void
    @State private var hovered = false
    @AppStorage(AppPreferences.densityKey) private var density = AppPreferences.defaultDensity
    @Environment(\.rowActive) private var rowActive
    private static let titleLine: CGFloat = 17, detailLine: CGFloat = 15

    var body: some View {
        HStack(spacing: SidebarMetrics.inset) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: "terminal")
                    .font(.scaled(14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: SidebarMetrics.lineGap) {
                Text(summary.title)
                    .font(SidebarMetrics.item)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: Self.titleLine, alignment: .leading)
                Text(detailText)
                    .font(SidebarMetrics.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: Self.detailLine, alignment: .leading)
            }
            Spacer(minLength: 4)
            if hovered || rowActive {
                IconButton(icon: "xmark", name: "Close terminal", action: close)
                    .opacity(hovered ? 1 : 0)
            }
        }
        .padding(.horizontal, density.rowPadding)
        .padding(.vertical, density.rowPadding)
        .onHover { hovered = $0 }
        .help("\(summary.title)\n\(summary.workingDirectory)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(summary.title), \(detailText)")
    }

    private var detailText: String {
        let path = abbreviatedTerminalPath(summary.workingDirectory)
        var parts = [path]
        if summary.tabCount > 1 {
            parts.append("\(summary.tabCount) tabs")
        }
        if summary.totalPaneCount > summary.tabCount {
            parts.append("\(summary.totalPaneCount) panes")
        }
        return parts.joined(separator: " · ")
    }
}
