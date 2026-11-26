import AppKit
import CarrierCore
import CarrierUI
import SwiftUI

// The sidebar of the Settings window: its pages in groups, and what the search found when there is a query.

/// The pages in groups, as the sidebar of System Settings lists its own: a colored tile with the page's symbol before its name.
struct SettingsSidebar: View {
    let navigator: SettingsNavigator
    @Binding var query: String
    @ObservedObject private var setup = SetupController.shared

    var body: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { pages } else { results }
    }

    private var pages: some View {
        List(selection: Binding(get: { navigator.page }, set: { if let page = $0 { navigator.go(page) } })) {
            ForEach(SettingsPage.Group.allCases, id: \.self) { group in
                if let heading = group.heading() {
                    Section(heading) { rows(group) }
                } else {
                    Section { rows(group) }
                }
            }
        }
        .listStyle(.sidebar)
        // the theme's color, as the main window's sidebar has it, and not the system's material
        .scrollContentBackground(.hidden).themedSidebarBackground()
    }

    /// The providers, accounts and servers of this Mac, which the static index cannot know: the Providers page's own answer, when it has one.
    private var providersEntries: [SettingsEntry] {
        guard case .reply(let reply) = AppHealth.providers.outcome, reply.problem == nil else { return [] }
        return providersSearchEntries(providersPage(reply, config: currentConfig(), chat: try? currentChatConfig()))
    }

    /// What the search found, under the pages it is in; choosing one opens the page and shows the row.
    @ViewBuilder private var results: some View {
        let found = settingsResults(query, in: settingsIndex + providersEntries)
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if found.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                ForEach(SettingsPage.allCases.filter { page in found.contains { $0.page == page } }, id: \.self) { page in
                    Section {
                        ForEach(found.filter { $0.page == page }) { entry in
                            Button {
                                navigator.open(entry)
                                query = ""
                            } label: {
                                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                                    Text(marked(entry.title, words: words))
                                    Text(marked(entry.isPage ? entry.detail : [entry.group, entry.detail].filter { !$0.isEmpty }.joined(separator: " · "), words: words))
                                        .scaledFont(11).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Label { Text(page.title()) } icon: { SettingsTile(page: page) }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden).themedSidebarBackground()
        }
    }

    /// The words of the search shown on what matched them.
    private func marked(_ text: String, words: [String]) -> AttributedString {
        var out = AttributedString(text)
        for word in words {
            var from = out.startIndex
            while let found = out[from...].range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
                out[found].backgroundColor = Color.yellow.opacity(0.45)
                from = found.upperBound
            }
        }
        return out
    }

    private func rows(_ group: SettingsPage.Group) -> some View {
        ForEach(SettingsPage.pages(in: group), id: \.self) { page in
            Label { Text(page.title()) } icon: { SettingsTile(page: page) }.tag(page).help(page.detail())
                // what Carrier is missing is fixed on these two pages: the sidebar says so, and the banner is on them alone
                .badge(page == .engine || page == .health ? missing : 0)
        }
    }

    private var missing: Int { readinessBanner(missing: setup.missing, detecting: setup.detecting).state == .missing ? 1 : 0 }
}

struct SettingsTile: View {
    let page: SettingsPage
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // the system's colors are made for a light window: on a dark one they glow, so they are mixed with black there
        Glyph(page.icon, size: 13, bold: true).foregroundStyle(.white.opacity(scheme == .dark ? 0.88 : 1))
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous).fill(page.tint.mix(with: .black, by: scheme == .dark ? 0.4 : 0.05)))
            .accessibilityHidden(true)
    }
}

extension SettingsPage {
    /// The color of the page's tile in the sidebar.
    var tint: Color {
        switch self {
        case .general, .engine, .keybindings: .gray
        case .providers: .purple
        case .appearance, .about: .blue
        case .notifications: .red
        case .dictation: .pink
        case .keepAwake: .yellow
        case .chat: .teal
        case .sessions: .indigo
        case .projects: .mint
        case .sidebar: .cyan
        case .terminal: Color(Tokens.Tile.terminal)
        case .roles: .orange
        case .watching, .health: .green
        case .behavior: .brown
        }
    }
}
