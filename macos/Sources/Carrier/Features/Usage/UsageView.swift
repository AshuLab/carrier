import AppKit
import CarrierCore
import SwiftUI

/// The one Usage state the window holds, asked of the real chat host (the fixture's under `--fixture`).
enum AppUsage {
    @MainActor static let store = UsageStore(host: SocketChatHost())
    @MainActor static let refresher = UsageRefresher(store: store)
}

/// The Usage page of the sidebar foot: the live quotas pooled by provider in one card (`usageProviders` decides every row), each provider with
/// its drawer, then the consumption (`ConsumptionSection`, docs/specs/usage-and-limits.md). The page has no automated test; the rows, the
/// meters' shapes, the numbers and the refresh triggers are `CarrierCore`'s.
struct UsageView: View {
    let store: UsageStore
    private let refresher = AppUsage.refresher
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s16) {
                // an older host is a normal state after an update: told quietly, as an engine too old to reload is
                let tooOld = store.error?.code == Refusal.usageNeedsNewerHost.code
                if tooOld {
                    Text(usageNeedsNewerHost).font(.scaled(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let problem = (tooOld ? nil : store.error?.shown()) ?? failure { ProblemLine(text: problem) }
                if store.quotas.isEmpty, store.error == nil {
                    SettingsTabCard {
                        if store.isLoading {
                            LoadingStateView(title: "Loading usage", line: "Checking your limits and what you have spent.").frame(minHeight: 240)
                        } else {
                            EmptyStateView(icon: .chartBar, title: "No accounts to show", line: "Limits show here once a provider is set up.").frame(minHeight: 240)
                        }
                    }
                } else {
                    // the countdowns follow the clock while the data waits for the next ask
                    TimelineView(.everyMinute) { context in
                        let providers = usageProviders(store.quotas, now: Int(context.date.timeIntervalSince1970 * 1000))
                        SettingsTabCard {
                            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                                if index > 0 { SettingsDivider() }
                                ProviderBlock(
                                    provider: provider, open: store.expandedProviders.contains(provider.id),
                                    toggleOpen: { store.toggleProvider(provider.id) }, checkAgain: { refresher.checkAgain() },
                                    signIn: { signIn($0, provider: provider.id) }
                                )
                            }
                        }
                    }
                }
                ConsumptionSection(store: store)
            }
            .padding(.vertical, Tokens.Space.s18).padding(.horizontal, Tokens.Space.s32).frame(maxWidth: .infinity)
        }
        .onAppear { refresher.appear() }
        .onDisappear { refresher.disappear() }
    }

    /// Opens Terminal on the account's login, as the Providers page does (the same script, the same opener; nothing is opened under `--fixture`).
    private func signIn(_ account: String, provider: String) {
        var command: String?, folder: String?
        if case .reply(let reply) = AppHealth.providers.outcome, let own = reply.accounts.first(where: { $0.name == account }) {
            command = own.command
            folder = own.configDir
        }
        let fixture = CommandLine.arguments.contains("--fixture")
        do {
            try providerInTerminal(
                .signIn, harness: provider, command: command, configDir: folder, opener: fixture ? FixtureTerminalOpener() : WorkspaceTerminalOpener()
            )
            failure = nil
        } catch {
            NSLog("Carrier: sign in to \(account) failed: %@", String(describing: error))
            failure = "Could not open Terminal to sign \(account) in."
        }
    }
}

/// A provider's header row and, open, its drawer. The whole row opens and closes the drawer; the filters by provider are in the filters row.
private struct ProviderBlock: View {
    let provider: UsageProviderRow
    let open: Bool
    let toggleOpen: () -> Void
    let checkAgain: () -> Void
    let signIn: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.none) {
            Button(action: toggleOpen) {
                HStack(spacing: Tokens.Space.s12) {
                    UsageProviderMark(title: provider.title, size: 18).frame(width: 22)
                    VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                        Text(provider.title).font(.scaled(13, weight: .semibold))
                        Text(provider.subtitle).font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(width: 150, alignment: .leading)
                    ForEach(Array(provider.meters.enumerated()), id: \.offset) { _, meter in
                        QuotaMeter(label: meter.kind.rawValue, shape: meter.shape).frame(width: 130)
                    }
                    Spacer(minLength: 0)
                    if provider.stale {
                        StatusChip(text: "Stale", tint: .orange)
                            .help("The provider is rate limiting the check: these are the last known numbers")
                    }
                    if let reset = provider.earliestReset {
                        Text(reset).font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    usageMark(provider.mark, provider.title)
                    Glyph(.chevronRight, size: 10).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 24, height: 24).background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .padding(.vertical, Tokens.Space.s12).frame(minHeight: 46).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides the details" : "Shows the details")
            if open {
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    ForEach(provider.accounts) { account in
                        AccountBlock(account: account, harness: provider.id, alone: provider.accounts.count == 1, checkAgain: checkAgain, signIn: { signIn(account.id) })
                    }
                }
                .padding(.leading, Tokens.Space.s34).padding(.bottom, Tokens.Space.s8)
            }
        }
        .animation(.easeOut(duration: 0.12), value: open)
    }
}

private func usageMark(_ mark: UsageMark, _ label: String) -> StatusMark {
    switch mark {
    case .ok: StatusMark(symbol: .check, color: .green, label: "\(label) is ready")
    case .warning: StatusMark(symbol: .exclamation, color: .yellow, label: "\(label) needs a look")
    case .failure: StatusMark(symbol: .close, color: .orange, label: "\(label) failed")
    }
}

/// One account or server pool of a drawer. Its own header (name, status, actions) shows only when it says something the provider's row does
/// not: several accounts, a status that is not ok, or an action. Under it, the rows in a panel per heading.
private struct AccountBlock: View {
    let account: UsageAccountRow
    /// The provider's name (`claude`, `codex`, `agy` or `local`): the mark an account has no icon of its own for.
    let harness: String
    let alone: Bool
    let checkAgain: () -> Void
    let signIn: () -> Void

    private var showsHeader: Bool { alone == false || account.mark != .ok || account.canSignIn || account.stale }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s14) {
            if showsHeader {
                HStack(spacing: Tokens.Space.s8) {
                    // a local server's pool is not an account of providers.json: it has no icon or color to wear
                    if harness != "local" { AccountMark(account: account.id, icon: harness, size: 14).help(account.title).accessibilityHidden(true) }
                    Text(account.title).font(.scaled(12, weight: .semibold))
                    Text(account.status).font(.scaled(11)).foregroundStyle(.secondary)
                    if account.stale { StatusChip(text: "Stale", tint: .orange) }
                    Spacer()
                    if account.canSignIn { Button("Sign in", action: signIn).buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).help("Opens Terminal and signs this account in") }
                    if account.mark != .ok { Button("Check again", action: checkAgain).buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small) }
                }
            }
            if let note = account.note { Text(note).font(.scaled(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            ForEach(Array(usageLineGroups(account.lines).enumerated()), id: \.offset) { _, group in
                LineGroupView(group: group)
            }
        }
        .padding(.vertical, Tokens.Space.s8)
    }
}

/// The rows under one heading, on a panel of their own with a line between them; a row with nothing but its words is a note under the panel.
private struct LineGroupView: View {
    let group: UsageLineGroup

    var body: some View {
        let rows = group.lines.filter { $0.shape != nil || $0.value != nil || $0.detail != nil }
        let notes = group.lines.filter { $0.shape == nil && $0.value == nil && $0.detail == nil }
        VStack(alignment: .leading, spacing: Tokens.Space.s6) {
            if let title = group.title { Text(title).sectionLabel().padding(.leading, Tokens.Space.s4) }
            if rows.isEmpty == false {
                VStack(spacing: Tokens.Space.none) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, line in
                        if index > 0 { SettingsDivider() }
                        LineRow(line: line).padding(.vertical, Tokens.Space.s10)
                    }
                }
                .padding(.horizontal, Tokens.Space.s12).background(RoundedRectangle(cornerRadius: Tokens.Radius.tile).fill(Color.primary.opacity(0.05)))
            }
            ForEach(Array(notes.enumerated()), id: \.offset) { _, line in
                Text(line.title).font(.scaled(11)).foregroundStyle(.secondary).padding(.leading, Tokens.Space.s4)
            }
        }
    }
}

/// A row of a panel, in columns that line up from one row to the next: a meter row (name, bar, percent, reset), a server (its mark, name,
/// address and state) or a plain fact (name and value).
private struct LineRow: View {
    let line: UsageLine

    var body: some View {
        if let shape = line.shape {
            HStack(spacing: Tokens.Space.s14) {
                Text(line.title).font(.scaled(12)).lineLimit(1).frame(width: 90, alignment: .leading)
                QuotaBar(shape: shape).frame(maxWidth: 360)
                QuotaPercent(shape: shape).frame(width: 44, alignment: .trailing)
                Text(line.reset ?? "").font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1).frame(width: 120, alignment: .leading)
                Spacer(minLength: 0)
            }
        } else if let detail = line.detail {
            HStack(alignment: .top, spacing: Tokens.Space.s12) {
                UsageProviderMark(title: line.title.replacingOccurrences(of: " ", with: ""), size: 16).frame(width: 20)
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    Text(line.title).font(.scaled(12, weight: .medium))
                    Text(detail).font(.scaled(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let value = line.value { ServerState(text: value) }
            }
        } else {
            HStack(spacing: Tokens.Space.s10) {
                Text(line.title).font(.scaled(12))
                Spacer(minLength: 8)
                Text(line.value ?? "").font(.scaled(12)).foregroundStyle(.secondary)
            }
        }
    }
}

/// A server's state as the host words it: a dot, green while it is ready and grey otherwise, and the words (never the colour alone).
private struct ServerState: View {
    let text: String

    var body: some View {
        HStack(spacing: Tokens.Space.s6) {
            Circle().fill(text == "Ready" ? Color.green : Color.secondary.opacity(0.6)).frame(width: 7, height: 7)
            Text(text).font(.scaled(11)).foregroundStyle(.secondary)
        }
    }
}
