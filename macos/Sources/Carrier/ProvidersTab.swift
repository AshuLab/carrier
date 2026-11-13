import AppKit
import CarrierCore
import SwiftUI

/// The Providers page of Settings (docs/specs/providers-in-settings.md): the AI tools of this Mac in a list, and for the chosen one its version
/// and path with Update, its accounts with who uses each and Sign in for a signed-out one (`providersPage`) or, for a local server, its models.
/// A tool found with no account has an Add (`ProvidersStore.add`); an account has Edit (`AccountEditor`, with Remove) and a tool Add account
/// (`AddAccountForm`). The page has no automated test; the rows are `providersPage`'s and the
/// commands `providerCommand`'s.
struct ProvidersTabView: View {
    /// Use in an agent… on an account no role names: opens the Agents page.
    let openAgents: () -> Void
    private let store = AppHealth.providers
    @State private var selected = "claude"
    @State private var config: Data?
    @State private var chat: Data?
    @State private var looking = false
    @State private var failure: String?
    /// The account whose editor is open, or the tool whose Add account form is.
    @State private var editing: String?
    @State private var adding: String?

    var body: some View {
        let page: ProvidersPage? = if case .reply(let reply) = store.outcome, reply.problem == nil { providersPage(reply, config: config, chat: chat) } else { nil }
        VStack(alignment: .leading, spacing: 14) {
            if let note = store.outcome.note {
                Text(note).font(.callout).foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .settingsCard()
            }
            if let page {
                HStack(alignment: .top, spacing: 14) {
                    list(page).frame(width: 210)
                    detail(page).frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .task { await look() }
        // what the engine said to a save belongs to the tool it was made on: it does not follow the person to another or out of the page
        .onDisappear { store.dismissProblem() }
        .onChange(of: selected) { store.dismissProblem() }
        // back from Terminal or an editor, where a login or a file may have changed
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await look() } }
    }

    private func look() async {
        looking = true
        config = currentConfig()
        chat = try? currentChatConfig()
        await store.load()
        looking = false
    }

    private func list(_ page: ProvidersPage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            listLabel("AI tools")
            ForEach(page.tools) { tool in
                ProviderListRow(icon: tool.icon, symbol: nil, title: tool.title, line: tool.status.text, mark: tool.status.mark, selected: selected == tool.id) { selected = tool.id }
            }
            listLabel("Local servers").padding(.top, 8)
            ForEach(page.servers) { server in
                ProviderListRow(
                    icon: nil, symbol: server.id == "ollama" ? "server.rack" : "desktopcomputer", title: server.title, line: server.status,
                    mark: server.running ? .ok : .off, selected: selected == server.id
                ) { selected = server.id }
            }
        }
        .padding(8).settingsCard()
    }

    /// The name of what is chosen with its actions on the same line, as text: Update acts on this tool and Check again on all of them. The pill
    /// of a button shows while the pointer is over it.
    private func titleRow(_ title: String, update tool: ProviderTool?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title).font(.title3.weight(.semibold))
            Spacer(minLength: 8)
            if let tool {
                // none of the three can only check: Update installs, so it opens Terminal on the command
                Button("Update") { open(.update, harness: tool.id, command: tool.command, configDir: nil) }
                    .buttonStyle(HoverTextButtonStyle(tint: nil)).help("Opens Terminal and runs \(tool.id) update")
            }
            Button(looking ? "Checking…" : "Check again") { Task { await look() } }
                .buttonStyle(HoverTextButtonStyle(tint: nil)).disabled(looking).help("Look at this Mac again")
        }
    }

    /// A small uppercase label over a group of the list, as the groups of a page have.
    private func listLabel(_ title: String) -> some View {
        Text(title).sectionLabel().padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 2)
    }

    @ViewBuilder private func detail(_ page: ProvidersPage) -> some View {
        if let tool = page.tools.first(where: { $0.id == selected }) {
            // two distances: 4 inside a block (the name and its version) and 14 between blocks
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    titleRow(tool.title, update: versionLine(tool.version, tool.path) == nil ? nil : tool)
                    if let line = versionLine(tool.version, tool.path) {
                        Text(line).font(.scaled(11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                            .lineLimit(2).truncationMode(.middle).copyOnHover(tool.path ?? line)
                    }
                }
                if let failure { ProblemLine(text: failure, font: .caption) }
                // an editor that closed after a save the engine did not apply leaves its words here
                if editing == nil, adding == nil {
                    if let problem = store.editProblem { ProblemLine(text: problem, font: .caption) }
                    // not a problem: said quietly, as the other pages say that Carrier reads it when it starts
                    if let note = store.editNote { Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                switch tool.status {
                case .missing: EmptyStateView(icon: "arrow.down.circle", title: "\(tool.title) is not installed", line: "Not found on this Mac, so there are no accounts to show.").frame(minHeight: 260)
                case .foundNotAdded:
                    VStack(alignment: .leading, spacing: 8) {
                        note("Found on this Mac and not added as an account yet.")
                        HStack(spacing: 10) {
                            Button("Add") { Task { await store.add(harness: tool.id) } }.buttonStyle(SecondaryCapsuleButtonStyle()).disabled(store.busy)
                            if let problem = store.addProblem { ProblemLine(text: problem) }
                        }
                    }
                default:
                    SettingsGroup(title: "Accounts") {
                        ForEach(Array(tool.accounts.enumerated()), id: \.element.id) { index, account in
                            let edit = { store.dismissProblem(); adding = nil; editing = account.name }
                            SettingsTabRow(
                                title: account.title, detail: account.usedBy, first: index == 0, note: tool.id == "agy" ? nil : account.configDir ?? "This Mac's login"
                            ) {
                                HStack(spacing: 10) {
                                    AccountStateLabel(state: account.state)
                                    if account.state == .signedOut {
                                        Button("Sign in") { open(.signIn, harness: tool.id, command: account.command, configDir: account.configDir) }
                                            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).help("Opens Terminal and signs this account in")
                                    }
                                    if account.state == .ready, account.uses.isEmpty {
                                        Button("Use in an agent…", action: openAgents).buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).help("Opens Agents to pick \(account.name) for a role")
                                    }
                                    Button(action: edit) {
                                        Image(systemName: "chevron.right").font(.scaled(11, weight: .bold))
                                    }
                                    .buttonStyle(HoverTextButtonStyle(tint: nil)).disabled(editing == account.name)
                                    .accessibilityLabel("Edit \(account.name)").help("Edit \(account.name)")
                                }
                            }
                            // the whole row opens the editor; the buttons inside keep their own clicks
                            .contentShape(Rectangle()).onTapGesture { if editing != account.name { edit() } }
                        }
                    }
                    if let account = tool.accounts.first(where: { $0.name == editing }) {
                        AccountEditor(account: account, harness: tool.id, store: store) { editing = nil }.id(account.name)
                    } else if adding == tool.id {
                        AddAccountForm(harness: tool.id, store: store) { adding = nil }
                    } else if tool.id != "agy" {
                        Button("Add account") { store.dismissProblem(); editing = nil; adding = tool.id }
                            .buttonStyle(SecondaryCapsuleButtonStyle()).help("Another login of \(tool.title)")
                    }
                }
            }
        } else if let server = page.servers.first(where: { $0.id == selected }) {
            VStack(alignment: .leading, spacing: 10) {
                titleRow(server.title, update: nil)
                if server.running == false {
                    EmptyStateView(icon: "server.rack", title: "\(server.title) is not running", line: "Nothing answers. Start \(server.title) to see its models.").frame(minHeight: 260)
                } else if server.models.isEmpty {
                    EmptyStateView(icon: "cube", title: "No model loaded", line: "\(server.title) is running, with no model loaded.").frame(minHeight: 260)
                } else {
                    SettingsGroup(title: "Models") {
                        ForEach(Array(server.models.enumerated()), id: \.offset) { index, model in
                            SettingsTabRow(title: model, detail: "", first: index == 0, mono: true) { EmptyView() }
                        }
                    }
                }
            }
        }
    }

    /// Terminal's script and opener are Continue in Terminal's; under `--fixture` the opener only says what it would have run.
    private func open(_ action: ProviderAction, harness: String, command: String?, configDir: String?) {
        let fixture = CommandLine.arguments.contains("--fixture")
        do {
            try providerInTerminal(
                action, harness: harness, command: command, configDir: configDir,
                opener: fixture ? FixtureTerminalOpener() : WorkspaceTerminalOpener()
            )
            failure = nil
        } catch {
            NSLog("Carrier: provider \(action.rawValue) in Terminal failed: %@", String(describing: error))
            failure = error is ProviderCommandError ? "This account's folder or binary is not an absolute path, so nothing was opened." : "Could not open Terminal."
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .settingsCard()
    }

    /// "2.1.3 (Claude Code) · /opt/homebrew/bin/claude", whatever of the two there is.
    private func versionLine(_ version: String?, _ path: String?) -> String? {
        let parts = [version, path].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

}

/// An account's state as the list shows a tool's: a dot of its colour and the words, orange for what asks for an action.
private struct AccountStateLabel: View {
    let state: ToolState

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(state.words).font(.callout).foregroundStyle(state == .signedOut || state == .missing ? SessionRowView.attention : Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch state {
        case .ready: .green
        case .signedOut, .missing: .orange
        case .unknown: .gray
        }
    }
}

private extension ToolState {
    var words: String {
        switch self {
        case .ready: "Signed in"
        case .signedOut: "Signed out"
        case .missing: "Not installed"
        case .unknown: "Could not check"
        }
    }
}

private enum ProviderDot { case ok, problem, off }

private extension ProviderTool.Status {
    var mark: ProviderDot {
        switch self {
        case .ready: .ok
        case .signedOut, .missing: .problem
        case .unknown, .foundNotAdded: .off
        }
    }
}

/// A row of the list: the tool's mark, its name, its state in words and a dot of the state.
private struct ProviderListRow: View {
    let icon: String?
    let symbol: String?
    let title: String
    let line: String
    let mark: ProviderDot
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 10) {
                glyph.frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(.medium).lineLimit(1)
                    Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            }
            .padding(.horizontal, 8).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Color.secondary.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var glyph: some View {
        if let icon {
            ProviderMark(name: icon, size: 15)
        } else {
            Image(systemName: symbol ?? "questionmark.circle").font(.scaled(14)).foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch mark {
        case .ok: .green
        case .problem: .orange
        case .off: .gray
        }
    }
}
