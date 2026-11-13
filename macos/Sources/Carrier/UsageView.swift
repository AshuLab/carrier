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
            VStack(alignment: .leading, spacing: 16) {
                // an older host is a normal state after an update: told quietly, as an engine too old to reload is
                let tooOld = store.error == usageNeedsNewerHost
                if tooOld {
                    Text(usageNeedsNewerHost).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let problem = (tooOld ? nil : store.error) ?? failure { ProblemLine(text: problem) }
                if store.quotas.isEmpty, store.error == nil {
                    SettingsTabCard {
                        if store.isLoading {
                            LoadingStateView(title: "Loading usage", line: "Checking your limits and what you have spent.").frame(minHeight: 240)
                        } else {
                            EmptyStateView(icon: "chart.bar", title: "No accounts to show", line: "Limits show here once a provider is set up.").frame(minHeight: 240)
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
            .padding(.vertical, 18).padding(.horizontal, 32).frame(maxWidth: .infinity)
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
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggleOpen) {
                HStack(spacing: 12) {
                    UsageProviderMark(title: provider.title, size: 18).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
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
                    Image(systemName: "chevron.right").font(.scaled(10, weight: .bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 24, height: 24).background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .padding(.vertical, 12).frame(minHeight: 46).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides the details" : "Shows the details")
            if open {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(provider.accounts) { account in
                        AccountBlock(account: account, alone: provider.accounts.count == 1, checkAgain: checkAgain, signIn: { signIn(account.id) })
                    }
                }
                .padding(.leading, 34).padding(.bottom, 8)
            }
        }
        .animation(.easeOut(duration: 0.12), value: open)
    }
}

private func usageMark(_ mark: UsageMark, _ label: String) -> StatusMark {
    switch mark {
    case .ok: StatusMark(symbol: "checkmark", color: .green, label: "\(label) is ready")
    case .warning: StatusMark(symbol: "exclamationmark", color: .yellow, label: "\(label) needs a look")
    case .failure: StatusMark(symbol: "xmark", color: .orange, label: "\(label) failed")
    }
}

/// One account or server pool of a drawer. Its own header (name, status, actions) shows only when it says something the provider's row does
/// not: several accounts, a status that is not ok, or an action. Under it, the rows in a panel per heading.
private struct AccountBlock: View {
    let account: UsageAccountRow
    let alone: Bool
    let checkAgain: () -> Void
    let signIn: () -> Void

    private var showsHeader: Bool { alone == false || account.mark != .ok || account.canSignIn || account.stale }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                HStack(spacing: 8) {
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
        .padding(.vertical, 8)
    }
}

/// The rows under one heading, on a panel of their own with a line between them; a row with nothing but its words is a note under the panel.
private struct LineGroupView: View {
    let group: UsageLineGroup

    var body: some View {
        let rows = group.lines.filter { $0.shape != nil || $0.value != nil || $0.detail != nil }
        let notes = group.lines.filter { $0.shape == nil && $0.value == nil && $0.detail == nil }
        VStack(alignment: .leading, spacing: 6) {
            if let title = group.title { Text(title).sectionLabel().padding(.leading, 4) }
            if rows.isEmpty == false {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, line in
                        if index > 0 { SettingsDivider() }
                        LineRow(line: line).padding(.vertical, 9)
                    }
                }
                .padding(.horizontal, 12).background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            }
            ForEach(Array(notes.enumerated()), id: \.offset) { _, line in
                Text(line.title).font(.scaled(11)).foregroundStyle(.secondary).padding(.leading, 4)
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
            HStack(spacing: 14) {
                Text(line.title).font(.scaled(12)).lineLimit(1).frame(width: 90, alignment: .leading)
                QuotaBar(shape: shape).frame(maxWidth: 360)
                QuotaPercent(shape: shape).frame(width: 44, alignment: .trailing)
                Text(line.reset ?? "").font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1).frame(width: 120, alignment: .leading)
                Spacer(minLength: 0)
            }
        } else if let detail = line.detail {
            HStack(alignment: .top, spacing: 12) {
                UsageProviderMark(title: line.title.replacingOccurrences(of: " ", with: ""), size: 16).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.title).font(.scaled(12, weight: .medium))
                    Text(detail).font(.scaled(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if let value = line.value { ServerState(text: value) }
            }
        } else {
            HStack(spacing: 10) {
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
        HStack(spacing: 6) {
            Circle().fill(text == "Ready" ? Color.green : Color.secondary.opacity(0.6)).frame(width: 7, height: 7)
            Text(text).font(.scaled(11)).foregroundStyle(.secondary)
        }
    }
}

/// A quota's track, 8 pt: the use that stays is solid (the theme's accent, orange from 90 %) and the use the next reset gives back is hatched
/// after it. The pieces below are the ones to use for any percentage: `QuotaPercent` is its number, `QuotaMeter` a label, the number and the bar.
struct QuotaBar: View {
    let shape: MeterShape
    var height: CGFloat = 8

    var body: some View {
        let tint = quotaTint(shape)
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Color.primary.opacity(0.12)
                LinearGradient(colors: [tint.opacity(0.8), tint], startPoint: .leading, endPoint: .trailing).frame(width: width * shape.solid)
                Hatch().stroke(tint, lineWidth: 1.5).background(tint.opacity(0.3)).frame(width: width * shape.hatched).offset(x: width * shape.solid)
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .frame(height: height).animation(.easeOut(duration: 0.25), value: shape.used).accessibilityHidden(true)
    }
}

private func quotaTint(_ shape: MeterShape) -> Color { shape.used >= 0.9 ? .orange : .themeAccent }

/// The percent of a quota: bold, and orange where the bar is.
struct QuotaPercent: View {
    let shape: MeterShape

    var body: some View {
        Text("\(Int((shape.used * 100).rounded()))%").font(.scaled(11, weight: .semibold)).monospacedDigit()
            .foregroundStyle(shape.used >= 0.9 ? Color.orange : Color.primary)
    }
}

/// A quota with its name and percent above its bar: the provider rows' meters.
struct QuotaMeter: View {
    let label: String
    let shape: MeterShape

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.scaled(11)).foregroundStyle(.secondary)
                Spacer()
                QuotaPercent(shape: shape)
            }
            QuotaBar(shape: shape)
        }
    }
}

private struct Hatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 4
        }
        return path
    }
}
