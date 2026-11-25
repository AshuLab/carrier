import CarrierCore
import CarrierUI
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
    /// Drawn as the section header of the scroll it is in, so its row stays at the top while the list moves under it.
    var pinHeader = false
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
        if pinHeader {
            // the open section's row stays at the top of the scroll while its list moves under it
            Section { list } header: { header.pinnedSectionHeader() }
        } else {
            header
            list
        }
    }

    @ViewBuilder private var header: some View {
        SidebarSectionRow(
            title: Copy.terminalSection(),
            icon: .terminal,
            selected: selected,
            keepActions: query != nil,
            action: select,
            actions: {
                if terminals.isEmpty == false {
                    Text("\(terminals.count)")
                        .sidebarFont(.detail, weight: .semibold).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, Tokens.Space.s6)
                        .padding(.vertical, Tokens.Space.s1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .accessibilityLabel(Copy.terminalCount(count: terminals.count))
                }
            },
            hoverActions: {
                IconButton(
                    icon: .search,
                    name: Copy.terminalSearch(),
                    enabled: terminals.isEmpty == false,
                    why: Copy.terminalSearchNone(),
                    shortcut: "⌘F",
                    pressed: query != nil
                ) {
                    if query == nil { openSearch() } else { query = nil }
                }
                IconButton(icon: .plus, name: Copy.terminalNewHelp(), action: newTerminal)
            }
        )
        .help(Copy.terminalSection())
        .onChange(of: open) { if open == false { query = nil } }
        .onChange(of: searchRequest) { if searchRequest?.section == .terminal { openSearch() } }
    }

    @ViewBuilder private var list: some View {
        if open {
            let shownTerminals = filteredStandaloneTerminals(terminals, query: query ?? "")
            LazyVStack(alignment: .leading, spacing: SidebarMetrics.rowGap) {
                if query != nil {
                    SidebarSearchField(
                        placeholder: Copy.terminalSearch(),
                        text: Binding(get: { query ?? "" }, set: { query = $0 }),
                        focus: $searching,
                        close: { query = nil }
                    )
                }
                switch SidebarListState(shown: shownTerminals.count, of: terminals.count, query: query ?? "") {
                case .empty:
                    let empty = EmptyState.noTerminals
                    SidebarEmptyBlock(icon: empty.icon, title: empty.title(), line: empty.line()) {
                        // the pill of the title bar's New Terminal
                        AccentGlassPillButton(title: Copy.terminalNewButton(), icon: .plus, action: newTerminal)
                            .help(Copy.terminalNewSessionHelp())
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
                            Label(Copy.terminalOpen(), systemIcon: .terminal).labelStyle(.titleAndIcon)
                        }
                        Button {
                            _ = store.openTab(for: .terminal(summary.id), workingDirectory: summary.workingDirectory)
                            selection = .terminal(id: summary.id)
                        } label: {
                            Label(Copy.terminalNewTab(), systemIcon: .copyPlus).labelStyle(.titleAndIcon)
                        }
                        Divider()
                        Button(role: .destructive) {
                            closeTerminal(summary.id)
                        } label: {
                            Label(Copy.terminalClose(), systemIcon: .close).labelStyle(.titleAndIcon)
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
    @AppStorage(Preference.appearanceDensity) private var density
    @Environment(\.rowActive) private var rowActive
    private static let titleLine: CGFloat = 17, detailLine: CGFloat = 15

    var body: some View {
        HStack(spacing: SidebarMetrics.inset) {
            ZStack {
                RoundedRectangle(cornerRadius: Tokens.Radius.tile)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 32, height: 32)
                Glyph(.terminal, size: 14)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: SidebarMetrics.lineGap) {
                Text(summary.title())
                    .sidebarFont(.item)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: Self.titleLine, alignment: .leading)
                Text(summary.subtitle())
                    .sidebarFont(.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(height: Self.detailLine, alignment: .leading)
            }
            Spacer(minLength: 4)
            if hovered || rowActive {
                IconButton(icon: .close, name: Copy.terminalCloseTerminalName(), action: close)
                    .opacity(hovered ? 1 : 0)
            }
        }
        .padding(.horizontal, density.rowPadding)
        .padding(.vertical, density.rowPadding)
        .onHover { hovered = $0 }
        .help(Copy.terminalRowHelp(title: summary.title(), folder: summary.workingDirectory))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Copy.terminalRowLabel(title: summary.title(), subtitle: summary.subtitle()))
        .accessibilityAction(named: Copy.terminalClose(), close)
    }
}
