import CarrierCore
import CarrierUI
import SwiftUI

/// The centre when the Terminal row is selected: toolbar Search and New Terminal, the empty state when none are open, or the list
/// of standalone terminal instances. Mirrors `SessionsHomeView.swift`.
struct TerminalsHomeView: View {
    let store: CarrierTerminalStore
    let newTerminal: () -> Void
    let select: (UUID) -> Void
    let closeTerminal: (UUID) -> Void

    @State private var query: String?
    @FocusState private var searching: Bool
    @FocusState private var listFocused: Bool
    @State private var highlighted: UUID?

    private var terminals: [StandaloneTerminalSummary] { store.standaloneTerminals() }

    var body: some View {
        let shown = filteredStandaloneTerminals(terminals, query: query ?? "")
        terminalsContent(terminals: shown)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .toolbar { toolbar }
    }

    @ViewBuilder private func terminalsContent(terminals shown: [StandaloneTerminalSummary]) -> some View {
        if terminals.isEmpty {
            EmptyStateView(
                state: .noTerminals,
                action: (Copy.terminalNewSession(), newTerminal),
                actionIcon: .plus,
                actionStyle: .accentGlass
            )
            .inPageScroll()
        } else if shown.isEmpty {
            EmptyStateView(
                state: .noResults,
                action: (Copy.terminalClearSearch(), { query = nil })
            )
            .inPageScroll()
        } else {
            let ids = shown.map(\.id)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        ForEach(shown) { summary in
                            TerminalHomeRow(
                                summary: summary,
                                highlighted: highlighted == summary.id && listFocused,
                                open: { select(summary.id) },
                                newTab: {
                                    _ = store.openTab(for: .terminal(summary.id), workingDirectory: summary.workingDirectory)
                                    select(summary.id)
                                },
                                close: { closeTerminal(summary.id) }
                            )
                            .id(summary.id)
                        }
                    }
                    .padding(.horizontal, Tokens.Space.s12)
                    .padding(.vertical, Tokens.Space.s8)
                }
                .focusable()
                .focused($listFocused)
                .focusEffectDisabled()
                .onKeyPress(.downArrow) { move(1, in: ids, proxy) }
                .onKeyPress(.upArrow) { move(-1, in: ids, proxy) }
                .onAppear { listFocused = true }
                .onKeyPress(.return) {
                    guard let highlighted, ids.contains(highlighted) else { return .ignored }
                    select(highlighted)
                    return .handled
                }
                .onKeyPress(keys: [.delete]) { press in
                    guard press.modifiers.contains(.command),
                          let highlighted, ids.contains(highlighted)
                    else { return .ignored }
                    closeTerminal(highlighted)
                    return .handled
                }
            }
        }
    }

    private func move(_ step: Int, in ids: [UUID], _ proxy: ScrollViewProxy) -> KeyPress.Result {
        guard ids.isEmpty == false else { return .ignored }
        let current = highlighted.flatMap(ids.firstIndex(of:))
        let next = current.map { min(max($0 + step, 0), ids.count - 1) } ?? (step > 0 ? 0 : ids.count - 1)
        highlighted = ids[next]
        proxy.scrollTo(ids[next])
        return .handled
    }

    /// Search pill when terminals exist, plus New Terminal on the right as the primary accent pill (mirroring `SessionsHomeView`).
    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if terminals.isEmpty == false {
            ToolbarItem(placement: .primaryAction) {
                searchItem
                    .glassEffect(.regular, in: .capsule)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(placement: .primaryAction) {
            AccentGlassPillButton(title: Copy.terminalNewButton(), icon: .plus, action: newTerminal)
                .padding(.trailing, Tokens.Space.s10)
                .help(Copy.terminalNewHelp())
        }
        .sharedBackgroundVisibility(.hidden)
    }

    @ViewBuilder private var searchItem: some View {
        ToolbarSearchField(query: $query, placeholder: Copy.terminalSearch(), focused: $searching) {
            listFocused = true
        }
    }
}

private struct TerminalHomeRow: View {
    let summary: StandaloneTerminalSummary
    let highlighted: Bool
    let open: () -> Void
    let newTab: () -> Void
    let close: () -> Void
    @State private var hovered = false

    var body: some View {
        let active = hovered || highlighted
        HStack(alignment: .center, spacing: Tokens.Space.s12) {
            ZStack {
                RoundedRectangle(cornerRadius: Tokens.Radius.tile)
                    .fill(Color.secondary.opacity(0.14))
                    .frame(width: 36, height: 36)
                Glyph(.terminal, size: 16)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text(summary.title())
                    .scaledFont(13, weight: .medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: Tokens.Space.s6) {
                    Label(abbreviatedTerminalPath(summary.workingDirectory), icon: .folder)
                        .labelStyle(.titleAndIcon)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let counts = summary.countsSummary() {
                        Text("·")
                        Text(counts)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if active {
                IconButton(icon: .close, name: Copy.terminalCloseNamed(title: summary.title()), action: close)
            }
        }
        .padding(.horizontal, Tokens.Space.s10)
        .padding(.vertical, Tokens.Space.s8)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(active ? Color.primary.opacity(0.07) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onMiddleClick(perform: close)
        .onHover { hovered = $0 }
        .contextMenu {
            Button(action: open) {
                Label(Copy.terminalOpen(), systemIcon: .terminal).labelStyle(.titleAndIcon)
            }
            Button(action: newTab) {
                Label(Copy.terminalNewTab(), systemIcon: .copyPlus).labelStyle(.titleAndIcon)
            }
            Divider()
            Button(role: .destructive, action: close) {
                Label(Copy.terminalClose(), systemIcon: .close).labelStyle(.titleAndIcon)
            }
        }
        .help(Copy.terminalRowHelp(title: summary.title(), folder: summary.workingDirectory))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Copy.terminalOpen(), open)
        .accessibilityAction(named: Copy.terminalNewTab(), newTab)
        .accessibilityAction(named: Copy.terminalClose(), close)
    }
}
