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
    private let store = AppHealth.providers
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
                SettingsGroup(title: "") { Text(note).font(.scaled(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            // Sign in opens Terminal from a provider's screen and from an account's: what went wrong is said where it was asked
            if let failure { SettingsGroup(title: "") { ProblemLine(text: failure, font: .scaled(11)) } }
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
        Button { Task { await look(refresh: true) } } label: { Label(looking ? "Checking…" : "Check again", icon: .refresh).labelStyle(.titleAndIcon) }
            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(looking).fixedSize()
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
            SettingsGroup(title: "Accounts that need attention") {
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
            SettingsGroup(title: "AI providers") {
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
            SettingsGroup(title: "Local servers") {
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
        checkGroup
    }

    // MARK: a provider

    @ViewBuilder private func providerScreen(_ tool: ProviderTool) -> some View {
        // an editor that closed after a save the engine did not apply leaves its words here
        if let problem = store.editProblem { SettingsGroup(title: "") { ProblemLine(text: problem, font: .scaled(11)) } }
        // not a problem: said quietly, as the other pages say that Carrier reads it when it starts
        if let note = store.editNote {
            SettingsGroup(title: "") { Label(note, icon: .info).font(.scaled(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        switch tool.status {
        case .missing:
            SettingsGroup(title: "") { EmptyStateView(icon: .download, title: "\(tool.title) is not installed", line: "Not found on this Mac, so there are no accounts to show.").frame(minHeight: 260) }
            checkGroup
        case .foundNotAdded:
            SettingsGroup(title: "") {
                SettingsTabRow(title: "Found on this Mac", detail: "Not added as an account yet", first: true) {
                    HStack(spacing: 10) {
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
                HStack(spacing: 8) {
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

/// An account of a provider, with its own usage: its name and state, who uses it and where its login lives and, at the right, its 5h and Weekly
/// meters with when they reset (or Sign in, for a signed-out one). When that does not fit (a narrow window, the largest text) the meters go under
/// the text. The whole row opens the account; the buttons inside keep their own clicks.
private struct AccountRow: View {
    let tool: ProviderTool
    let account: ProviderAccount
    let usage: AccountUsage?
    let signIn: () -> Void
    let edit: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                AccountTile(account: account.name, icon: tool.icon)
                text.frame(maxWidth: 300, alignment: .leading)
                Spacer(minLength: 8)
                trailing
                chevron
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    AccountTile(account: account.name, icon: tool.icon)
                    text
                    Spacer(minLength: 8)
                    chevron
                }
                trailing
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle()).onTapGesture(perform: edit)
    }

    private var chevron: some View {
        Button(action: edit) { Glyph(.chevronRight, size: 13, bold: true).foregroundStyle(.tertiary) }
            .buttonStyle(HoverTextButtonStyle(tint: nil)).accessibilityLabel("Edit \(account.name)").help("Edit \(account.name)")
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                // the state is told to VoiceOver here too: with cached quotas the row shows their bars and not the state's words
                Circle().fill(account.state.color).frame(width: 7, height: 7).accessibilityLabel(account.state.words)
                Text(account.title).fontWeight(.medium)
            }
            // one line, with the whole of it as a tooltip: who uses the account is on its own screen too
            Text(account.usedBy).font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail).help(account.usedBy)
            if tool.id != "agy" {
                let folder = account.configDir ?? "This Mac's login"
                Text(folder).font(.scaled(10.5, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .help(folder).textSelection(.enabled)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        if account.state == .signedOut {
            HStack(spacing: 10) {
                AccountStateLabel(state: account.state)
                Button("Sign in", action: signIn).buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).fixedSize().help("Opens Terminal and signs this account in")
            }
        } else if let usage {
            AccountUsageMeters(usage: usage)
        } else {
            AccountStateLabel(state: account.state)
        }
    }
}

/// An account's quotas: 5h, Weekly and Monthly, each a bar with its percent, and under them when the 5h resets and whether the numbers are the last known.
struct AccountUsageMeters: View {
    let usage: AccountUsage

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            if let five = usage.five { UsageMeterLine(label: "5h", shape: five) }
            if let weekly = usage.weekly { UsageMeterLine(label: "Weekly", shape: weekly) }
            if let monthly = usage.monthly { UsageMeterLine(label: "Monthly", shape: monthly) }
            if usage.stale || usage.reset != nil {
                HStack(spacing: 6) {
                    if usage.stale { StatusChip(text: "Stale", tint: .orange) }
                    if let reset = usage.reset { Text(reset).lineLimit(1) }
                }
                .font(.scaled(10.5)).foregroundStyle(.secondary).fixedSize()
            }
        }
        // room for the words and the percent at the largest text, and no more than the bars need
        .frame(minWidth: 220, maxWidth: 280)
        .accessibilityElement(children: .combine)
    }
}

/// A label, a bar and the percent on one line: the Usage page's own `QuotaBar` and `QuotaPercent`, thinner.
struct UsageMeterLine: View {
    let label: String
    let shape: MeterShape

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1).fixedSize().frame(minWidth: 46, alignment: .leading)
            QuotaBar(shape: shape, height: 5).frame(minWidth: 60, maxWidth: .infinity)
            QuotaPercent(shape: shape).lineLimit(1).fixedSize().frame(minWidth: 36, alignment: .trailing)
        }
    }
}

/// A state as words with a dot of its color, orange for what needs someone.
private struct StateWords: View {
    let text: String
    let mark: DirectoryProvider.Mark

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(text).font(.scaled(12)).foregroundStyle(mark == .attention ? SessionRowView.attention : Color.secondary).lineLimit(1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch mark {
        case .ok: .green
        case .attention: .orange
        case .off: .gray
        }
    }
}

/// A provider's avatar: its mark (or a symbol, for a local server) in a rounded square at the left of its row.
private struct ProviderTile: View {
    let icon: String?
    let symbol: AppIcon?

    var body: some View {
        Group {
            if let icon { ProviderMark(name: icon, size: 20) } else { Glyph(symbol ?? .help, size: 18).foregroundStyle(.secondary) }
        }
        .frame(width: 38, height: 38).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
        .accessibilityHidden(true)
    }
}

/// An account's avatar: its mark (the tool's, or the icon and colour the person chose) large in a rounded square, at the left of its row.
private struct AccountTile: View {
    let account: String
    let icon: String

    var body: some View {
        AccountMark(account: account, icon: icon, size: 22)
            .frame(width: 38, height: 38).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
            .accessibilityHidden(true)
    }
}

/// An account's state: a dot of its colour and the words, orange for what asks for an action.
private struct AccountStateLabel: View {
    let state: ToolState

    var body: some View { StateWords(text: state.words, mark: state.mark) }
}

private extension ToolState {
    var mark: DirectoryProvider.Mark {
        switch self {
        case .ready: .ok
        case .signedOut, .missing: .attention
        case .unknown: .off
        }
    }

    var color: Color {
        switch self {
        case .ready: .green
        case .signedOut, .missing: .orange
        case .unknown: .gray
        }
    }

    var words: String {
        switch self {
        case .ready: "Signed in"
        case .signedOut: "Signed out"
        case .missing: "Not installed"
        case .unknown: "Could not check"
        }
    }
}
