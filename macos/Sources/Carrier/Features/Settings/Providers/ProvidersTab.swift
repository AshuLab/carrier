import AppKit
import CarrierCore
import SwiftUI

/// The Providers page of Settings (docs/specs/providers-in-settings.md), three screens of one form, each a place of the window's history (‹ ›):
/// the list of providers (the accounts that need someone first, the providers with how many accounts each has, the local servers), one provider
/// (its accounts, each with its own 5h and Weekly usage, and its version) and one account (its editor, with Save in the toolbar). The rows and
/// the numbers are `providersDirectory`'s and `providersPage`'s; the page has no automated test of its own.
struct ProvidersTabView: View {
    /// Where the page is: nothing, a provider, or an account of it (or a form that adds one).
    let place: SettingsPlace
    let go: (SettingsPlace) -> Void
    let back: () -> Void
    /// Use in an agent… on an account no role names: opens the Agents page.
    let openAgents: () -> Void
    let store = AppHealth.providers
    private let usage = AppUsage.store
    @State private var config: Data?
    @State private var chat: Data?
    @State private var looking = false
    @State private var failure: String?
    @State private var filter = ""
    @State private var showsAllAttention = false
    /// A write closed the editor: what the engine says of it comes after, and must survive the move to the provider's screen.
    @State private var keepsMessage = false

    /// The path of the form that adds an account to a provider: `[provider, "+"]`.
    static let addAccountPath = "+"
    private static let attentionShown = 5

    var body: some View {
        let page: ProvidersPage? = if case .reply(let reply) = store.outcome, reply.problem == nil { providersPage(reply, config: config, chat: chat) } else { nil }
        SettingsPageBody {
            if let note = store.outcome.note {
                SettingsGroup(title: "") { Text(note).scaledFont(12).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            // Sign in opens Terminal from a provider's screen and from an account's: what went wrong is said where it was asked
            if let failure { SettingsGroup(title: "") { ProblemLine(text: failure, size: 11) } }
            if let page { screen(page) }
        }
        .preference(key: SettingsTitleKey.self, value: page.flatMap(title))
        .task { await look() }
        // what a screen said (a refusal of the editor, the engine's answer to a save) belongs to that screen: it does not follow the person to another or
        // out of the page. Only the close after a successful write keeps it, since the engine answers after the editor is gone
        .onDisappear { store.dismissProblem() }
        .onChange(of: place) {
            failure = nil
            if keepsMessage { keepsMessage = false } else { store.dismissProblem() }
        }
        // back from Terminal or an editor, where a login or a file may have changed
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in Task { await look() } }
    }

    /// `refresh` skips the host's minute of cache for the quotas (Check again); otherwise the page takes what it has.
    private func look(refresh: Bool = false) async {
        looking = true
        config = currentConfig()
        chat = try? currentChatConfig()
        await store.load()
        // the quotas belong to the accounts the page lists: asked with them, once
        await usage.load(refresh: refresh)
        looking = false
    }

    /// Check again, on every screen that has none of its own: after Carrier starts a server or a CLI is installed, the page can be asked to look.
    private var checkButton: some View {
        CheckAgainButton(checking: looking) { Task { await look(refresh: true) } }
    }

    private var checkGroup: some View {
        SettingsGroup(title: "") {
            SettingsTabRow(title: "Look at this Mac again", detail: "Providers, sign-ins and each account's quota", first: true) { checkButton }
        }
    }

    private func here(_ path: String...) -> SettingsPlace { SettingsPlace(.providers, path: path) }

    /// What the editors call once their write went through: back to the provider, keeping what the engine will say of it.
    private func leaveAfterWrite() {
        keepsMessage = true
        back()
    }

    // MARK: which screen

    @ViewBuilder private func screen(_ page: ProvidersPage) -> some View {
        if let id = place.path.first, let tool = page.tools.first(where: { $0.id == id }) {
            if place.path.count > 1, place.path[1] == Self.addAccountPath {
                AddAccountForm(harness: tool.id, store: store, close: leaveAfterWrite)
            } else if place.path.count > 1, let account = tool.accounts.first(where: { $0.name == place.path[1] }) {
                accountScreen(tool, account)
            } else {
                providerScreen(tool)
            }
        } else if let id = place.path.first, let server = page.servers.first(where: { $0.id == id }) {
            serverScreen(server)
        } else {
            directory(page)
        }
    }

    /// What the toolbar says of the screen: the provider's name and how many accounts it has, the account's name and whose it is.
    private func title(_ page: ProvidersPage) -> SettingsTitle? {
        guard let id = place.path.first else { return nil }
        if let tool = page.tools.first(where: { $0.id == id }) {
            if place.path.count > 1, place.path[1] == Self.addAccountPath { return SettingsTitle(text: "Add account", subtitle: tool.title) }
            if place.path.count > 1, let account = tool.accounts.first(where: { $0.name == place.path[1] }) {
                return SettingsTitle(text: account.title, subtitle: "\(tool.title) account")
            }
            return SettingsTitle(text: tool.title, subtitle: tool.accounts.isEmpty ? tool.status.text : "\(tool.accounts.count) \(tool.accounts.count == 1 ? "account" : "accounts")")
        }
        return page.servers.first { $0.id == id }.map { SettingsTitle(text: $0.title, subtitle: $0.status) }
    }

    // MARK: the list

    @ViewBuilder private func directory(_ page: ProvidersPage) -> some View {
        let list = providersDirectory(page, quotas: usage.quotas, filter: filter, now: Int(Date().timeIntervalSince1970 * 1000))
        SettingsGroup(title: "") {
            TextField("", text: $filter, prompt: Text("Filter providers and accounts")).accessibilityLabel("Filter providers and accounts").settingsField(icon: .search).writingToolsBehavior(.disabled)
        }
        if list.isEmpty {
            SettingsGroup(title: "") { Text("Nothing matches “\(filter)”").foregroundStyle(.secondary) }
        }
        if list.attention.isEmpty == false {
            let shown = showsAllAttention ? list.attention : Array(list.attention.prefix(Self.attentionShown))
            SettingsGroup(id: "accounts-that-need-attention", title: "Accounts that need attention") {
                ForEach(shown) { item in
                    NavigationRow(
                        title: item.account.title, detail: item.toolTitle, leading: AccountTile(account: item.account.name, icon: item.icon),
                        action: { go(here(item.tool)); go(here(item.tool, item.account.name)) }
                    ) {
                        if item.reason == .signedOut {
                            AccountStateLabel(state: .signedOut)
                        } else if let five = item.usage?.five {
                            UsageMeterLine(label: "5h", shape: five).frame(width: 190)
                        }
                    }
                }
                if list.attention.count > shown.count {
                    Button("Show \(list.attention.count - shown.count) more") { showsAllAttention = true }.buttonStyle(HoverTextButtonStyle(tint: nil))
                }
            }
        }
        if list.providers.isEmpty == false {
            SettingsGroup(id: "ai-providers", title: "AI providers") {
                ForEach(list.providers) { provider in
                    NavigationRow(
                        title: provider.tool.title, detail: provider.accounts == 1 ? "1 account" : "\(provider.accounts) accounts",
                        leading: ProviderTile(icon: provider.tool.icon, symbol: nil), action: { go(here(provider.tool.id)) }
                    ) {
                        StateWords(text: provider.summary, mark: provider.mark)
                    }
                }
            }
        }
        if list.servers.isEmpty == false {
            SettingsGroup(id: "local-servers", title: "Local servers") {
                ForEach(list.servers) { server in
                    NavigationRow(
                        title: server.title, detail: "", leading: ProviderTile(icon: nil, symbol: server.id == "ollama" ? .server : .desktop),
                        action: { go(here(server.id)) }
                    ) {
                        StateWords(text: server.status, mark: server.running ? .ok : .off)
                    }
                }
            }
        }
        if filter.isEmpty { textGeneratorsGroup(page) }
        checkGroup
    }

    // MARK: a provider

    @ViewBuilder private func providerScreen(_ tool: ProviderTool) -> some View {
        // an editor that closed after a save the engine did not apply leaves its words here
        if let problem = store.editProblem { SettingsGroup(title: "") { ProblemLine(text: problem, size: 11) } }
        // not a problem: said quietly, as the other pages say that Carrier reads it when it starts
        if let note = store.editNote {
            SettingsGroup(title: "") { Label(note, icon: .info).scaledFont(11).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        switch tool.status {
        case .missing:
            SettingsGroup(title: "") { EmptyStateView(icon: .download, title: "\(tool.title) is not installed", line: "Not found on this Mac, so there are no accounts to show.").frame(minHeight: 260) }
            checkGroup
        case .foundNotAdded:
            SettingsGroup(title: "") {
                SettingsTabRow(title: "Found on this Mac", detail: "Not added as an account yet", first: true) {
                    HStack(spacing: Tokens.Space.s10) {
                        if let problem = store.addProblem { ProblemLine(text: problem) }
                        Button("Add") { Task { await store.add(harness: tool.id) } }.buttonStyle(SecondaryCapsuleButtonStyle()).disabled(store.busy)
                    }
                }
            }
            details(tool)
        default:
            SettingsGroup(title: "Accounts", footer: "Each account has its own quota, even under one provider. The hatched part of a bar is what the next reset gives back.") {
                ForEach(tool.accounts) { account in
                    AccountRow(
                        tool: tool, account: account, usage: accountUsage(account.name, in: usage.quotas, now: Int(Date().timeIntervalSince1970 * 1000)),
                        signIn: { open(.signIn, harness: tool.id, command: account.command, configDir: account.configDir) },
                        edit: { store.dismissProblem(); go(here(tool.id, account.name)) }
                    )
                }
                if tool.id != "agy" {
                    Button { store.dismissProblem(); go(here(tool.id, Self.addAccountPath)) } label: { Label("Add account", icon: .plus).labelStyle(.titleAndIcon) }
                        .buttonStyle(HoverTextButtonStyle(tint: nil)).help("Another login of \(tool.title)")
                }
            }
            details(tool)
        }
    }

    /// The provider's version and path, with Update (it installs, so it opens Terminal on the command), and the check that asks for the accounts
    /// and their quotas again; the history of tokens and cost is the Usage page's.
    @ViewBuilder private func details(_ tool: ProviderTool) -> some View {
        SettingsGroup(title: "Details") {
            SettingsTabRow(title: "Version", detail: tool.version ?? "Not known", first: true, note: tool.path) {
                if tool.version != nil || tool.path != nil {
                    Button("Update") { open(.update, harness: tool.id, command: tool.command, configDir: nil) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).help("Opens Terminal and runs \(tool.id) update")
                }
            }
            SettingsTabRow(title: "Sign-ins and quotas", detail: "Tokens and cost are on the Usage page") {
                HStack(spacing: Tokens.Space.s8) {
                    checkButton
                    Button("Open Usage") { WindowController.shared.showUsage() }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).fixedSize()
                }
            }
        }
    }

    // MARK: an account

    @ViewBuilder private func accountScreen(_ tool: ProviderTool, _ account: ProviderAccount) -> some View {
        if account.state == .signedOut {
            SettingsGroup(title: "") {
                SettingsTabRow(title: "Signed out", detail: "Sign in opens Terminal and signs this account in", first: true) {
                    Button("Sign in") { open(.signIn, harness: tool.id, command: account.command, configDir: account.configDir) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                }
            }
        }
        if account.state == .ready, account.uses.isEmpty {
            SettingsGroup(title: "") {
                SettingsTabRow(title: "Use in an agent", detail: "Opens Agents to pick \(account.name) for a role", first: true) {
                    Button("Open Agents", action: openAgents).buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                }
            }
        }
        AccountEditor(account: account, harness: tool.id, store: store, close: leaveAfterWrite).id(account.name)
    }

    // MARK: a local server

    @ViewBuilder private func serverScreen(_ server: ProviderServer) -> some View {
        if server.running == false {
            SettingsGroup(title: "") { EmptyStateView(icon: .server, title: "\(server.title) is not running", line: "Nothing answers. Start \(server.title) to see its models.").frame(minHeight: 260) }
        } else if server.models.isEmpty {
            SettingsGroup(title: "") { EmptyStateView(icon: .cube, title: "No model loaded", line: "\(server.title) is running, with no model loaded.").frame(minHeight: 260) }
        } else {
            SettingsGroup(title: "Models") {
                ForEach(Array(server.models.enumerated()), id: \.offset) { index, model in
                    SettingsTabRow(title: model, detail: "", first: index == 0, mono: true) { EmptyView() }
                }
            }
        }
        checkGroup
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
}
