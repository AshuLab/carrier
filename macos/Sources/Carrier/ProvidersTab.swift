import AppKit
import CarrierCore
import SwiftUI

/// The Providers page of Settings (docs/specs/providers-in-settings.md): the AI tools of this Mac in a list, and for the chosen one its version
/// and path with Update, its accounts with who uses each and Sign in for a signed-out one (`providersPage`) or, for a local server, its models.
/// A tool found with no account has an Add (`ProvidersStore.add`); an account has Edit (`AccountEditor`, with Remove) and a tool Add account
/// (`AddAccountForm`). The page has no automated test; the rows are `providersPage`'s and the
/// commands `providerCommand`'s.
struct ProvidersTabView: View {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("What this Mac has, as the chat host sees it.").font(.callout).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if looking { ProgressView().controlSize(.small) }
                Button("Check again") { Task { await look() } }.buttonStyle(.glass).buttonBorderShape(.capsule).disabled(looking)
            }
            .padding(.horizontal, 14)
            if let note = store.outcome.note {
                Text(note).font(.callout).foregroundStyle(.secondary).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
            }
            if case .reply(let reply) = store.outcome, reply.problem == nil {
                let page = providersPage(reply, config: config, chat: chat)
                HStack(alignment: .top, spacing: 14) {
                    list(page).frame(width: 210)
                    detail(page).frame(maxWidth: .infinity, alignment: .topLeading)
                }
                Text(providersFooter).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14)
            }
        }
        .task { await look() }
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
            ForEach(page.tools) { tool in
                ProviderListRow(icon: tool.icon, symbol: nil, title: tool.title, line: tool.status.text, mark: tool.status.mark, selected: selected == tool.id) { selected = tool.id }
            }
            Divider().padding(.vertical, 4)
            ForEach(page.servers) { server in
                ProviderListRow(
                    icon: nil, symbol: server.id == "ollama" ? "server.rack" : "desktopcomputer", title: server.title, line: server.status,
                    mark: server.running ? .ok : .off, selected: selected == server.id
                ) { selected = server.id }
            }
        }
        .padding(8).background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
    }

    @ViewBuilder private func detail(_ page: ProvidersPage) -> some View {
        if let tool = page.tools.first(where: { $0.id == selected }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tool.title).font(.title3.weight(.semibold))
                if let line = versionLine(tool.version, tool.path) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(line).font(.scaled(11.5, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                            .lineLimit(2).truncationMode(.middle)
                        Spacer(minLength: 8)
                        // none of the three can only check: Update installs, so it opens Terminal on the command
                        Button("Update") { open(.update, harness: tool.id, command: tool.command, configDir: nil) }
                            .controlSize(.small).help("Opens Terminal and runs \(tool.id) update")
                    }
                }
                if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
                switch tool.status {
                case .missing: note("Not installed on this Mac.")
                case .foundNotAdded:
                    VStack(alignment: .leading, spacing: 8) {
                        note("Found on this Mac and not added as an account yet.")
                        HStack(spacing: 10) {
                            Button("Add") { Task { await store.add(harness: tool.id) } }.buttonStyle(.glass).buttonBorderShape(.capsule)
                            if let problem = store.addProblem { Text(problem).font(.callout).foregroundStyle(.red) }
                        }
                    }
                default:
                    SettingsGroup(title: "Accounts") {
                        ForEach(Array(tool.accounts.enumerated()), id: \.element.id) { index, account in
                            SettingsTabRow(title: account.title, detail: accountLine(account, harness: tool.id), first: index == 0) {
                                HStack(spacing: 10) {
                                    Text(account.state.words).font(.callout).foregroundStyle(.secondary)
                                    if account.state == .signedOut {
                                        Button("Sign in") { open(.signIn, harness: tool.id, command: account.command, configDir: account.configDir) }
                                            .controlSize(.small).help("Opens Terminal and signs this account in")
                                    }
                                    Button("Edit") { store.dismissProblem(); adding = nil; editing = account.name }
                                        .controlSize(.small).disabled(editing == account.name).help("Edit \(account.name)")
                                }
                            }
                        }
                    }
                    if let account = tool.accounts.first(where: { $0.name == editing }) {
                        AccountEditor(account: account, harness: tool.id, store: store) { editing = nil }.id(account.name)
                    } else if adding == tool.id {
                        AddAccountForm(harness: tool.id, store: store) { adding = nil }
                    } else if tool.id != "agy" {
                        Button("Add account") { store.dismissProblem(); editing = nil; adding = tool.id }
                            .buttonStyle(.glass).buttonBorderShape(.capsule).help("Another login of \(tool.title)")
                    }
                }
            }
        } else if let server = page.servers.first(where: { $0.id == selected }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(server.title).font(.title3.weight(.semibold))
                if server.running == false {
                    note("Not running: nothing answers. Start \(server.title) to see its models.")
                } else if server.models.isEmpty {
                    note("Running, with no model loaded.")
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
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
    }

    /// "2.1.3 (Claude Code) · /opt/homebrew/bin/claude", whatever of the two there is.
    private func versionLine(_ version: String?, _ path: String?) -> String? {
        let parts = [version, path].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What the row says under the account: its config folder (none for the Mac's own login), whether it is off, and who uses it.
    private func accountLine(_ account: ProviderAccount, harness: String) -> String {
        var parts = [account.usedBy]
        if harness != "agy" { parts.append(account.configDir ?? "This Mac's login") }
        return parts.joined(separator: " · ")
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
