import AppKit
import CarrierCore
import SwiftUI

/// The one Usage state the window holds, asked of the real chat host (the fixture's under `--fixture`).
enum AppUsage {
    @MainActor static let store = UsageStore(host: SocketChatHost())
    @MainActor static let refresher = UsageRefresher(store: store)
}

/// The Usage page of the sidebar foot: the live quotas pooled by provider in one card (`usageProviders` decides every row), each provider with
/// its drawer. The consumption section comes in a later slice (docs/specs/usage-and-limits.md). The page has no automated test; the rows,
/// the meters' shapes and the refresh triggers are `CarrierCore`'s.
struct UsageView: View {
    let store: UsageStore
    private let refresher = AppUsage.refresher
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usage").font(.title3.weight(.semibold))
                        Text("Limits left and what was used, per account").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.isRefreshing { ProgressView().controlSize(.small) }
                    Button("Check again") { refresher.checkAgain() }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                        .disabled(store.isRefreshing).help("Asks every provider again, skipping the minute the chat host keeps its answer")
                }
                if let error = store.error ?? failure {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                }
                if store.quotas.isEmpty {
                    SettingsTabCard {
                        Text(store.isLoading ? "Asking the chat host…" : "No accounts to show")
                            .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
                    }
                } else {
                    // the countdowns follow the clock while the data waits for the next ask
                    TimelineView(.everyMinute) { context in
                        let providers = usageProviders(store.quotas, now: Int(context.date.timeIntervalSince1970 * 1000))
                        SettingsTabCard {
                            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                                if index > 0 { SettingsDivider() }
                                ProviderBlock(
                                    provider: provider, filtered: store.providerFilter == provider.id.asFilter,
                                    open: store.expandedProviders.contains(provider.id),
                                    toggleFilter: { store.toggleFilter(provider.id.asFilter); Task { await store.load() } },
                                    toggleOpen: { store.toggleProvider(provider.id) }, checkAgain: { refresher.checkAgain() },
                                    signIn: { signIn($0, provider: provider.id) }
                                )
                            }
                        }
                    }
                }
            }
            .padding(18).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }
        .onAppear { refresher.appear() }
        .onDisappear { refresher.disappear() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresher.appBecameActive() }
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

private extension String {
    var asFilter: UsageProviderFilter { UsageProviderFilter(rawValue: self) ?? .all }
}

/// A provider's header row and, open, its drawer. A click on the row filters the consumption by the provider; the chevron opens the drawer.
private struct ProviderBlock: View {
    let provider: UsageProviderRow
    let filtered: Bool
    let open: Bool
    let toggleFilter: () -> Void
    let toggleOpen: () -> Void
    let checkAgain: () -> Void
    let signIn: (String) -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button(action: toggleFilter) {
                    HStack(spacing: 12) {
                        usageMark(provider.mark, provider.title)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(provider.title).font(.scaled(13, weight: .semibold))
                            Text(provider.subtitle).font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(width: 150, alignment: .leading)
                        ForEach(Array(provider.meters.enumerated()), id: \.offset) { _, meter in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(meter.kind.rawValue).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int((meter.shape.used * 100).rounded()))%").monospacedDigit()
                                }
                                .font(.scaled(11))
                                QuotaBar(shape: meter.shape)
                            }
                            .frame(width: 104)
                        }
                        Spacer(minLength: 0)
                        if provider.stale {
                            Text("Stale").font(.scaled(10, weight: .semibold)).foregroundStyle(.orange)
                                .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Color.orange.opacity(0.15)))
                                .help("The provider is rate limiting the check: these are the last known numbers")
                        }
                        if let reset = provider.earliestReset {
                            Text(reset).font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(filtered ? .isSelected : [])
                .help(filtered ? "Showing the consumption of \(provider.title) only; click to show all" : "Show the consumption of \(provider.title) only")
                Button(action: toggleOpen) {
                    Image(systemName: "chevron.right").font(.scaled(11, weight: .bold)).rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(HoverTextButtonStyle(tint: nil)).accessibilityLabel(open ? "Hide \(provider.title) details" : "Show \(provider.title) details")
            }
            .padding(.vertical, 12).frame(minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.themeAccent.opacity(filtered ? 0.12 : hovered ? 0.05 : 0)).padding(.horizontal, -8))
            .onHover { hovered = $0 }
            if open {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(provider.accounts) { account in AccountBlock(account: account, checkAgain: checkAgain, signIn: { signIn(account.id) }) }
                }
                .padding(.leading, 28).padding(.bottom, 14)
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

/// One account or server pool of a drawer: its status, its actions and every row the provider gave.
private struct AccountBlock: View {
    let account: UsageAccountRow
    let checkAgain: () -> Void
    let signIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(account.title).font(.scaled(12, weight: .semibold))
                Text(account.status).font(.scaled(11)).foregroundStyle(.secondary)
                if account.stale { Text("Stale").font(.scaled(10, weight: .semibold)).foregroundStyle(.orange) }
                Spacer()
                if account.canSignIn { Button("Sign in", action: signIn).buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).help("Opens Terminal and signs this account in") }
                if account.mark != .ok { Button("Check again", action: checkAgain).buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small) }
            }
            if let note = account.note { Text(note).font(.scaled(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            ForEach(Array(account.lines.enumerated()), id: \.offset) { _, line in LineRow(line: line) }
        }
    }
}

private struct LineRow: View {
    let line: UsageLine

    var body: some View {
        if line.heading {
            Text(line.title).sectionLabel().padding(.top, 4)
        } else if let shape = line.shape {
            HStack(spacing: 10) {
                Text(line.title).font(.scaled(12)).lineLimit(1).frame(width: 130, alignment: .leading)
                QuotaBar(shape: shape).frame(maxWidth: 200)
                Text(line.value ?? "").font(.scaled(11)).monospacedDigit().frame(width: 36, alignment: .trailing)
                Text(line.reset ?? "").font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(line.title).font(.scaled(12)).foregroundStyle(line.value == nil ? .secondary : .primary)
                    if let value = line.value { Text(value).font(.scaled(12)).foregroundStyle(.secondary) }
                }
                if let detail = line.detail { Text(detail).font(.scaled(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

/// A 4 pt track: the use that stays solid and, after it, the use the next reset gives back, hatched.
private struct QuotaBar: View {
    let shape: MeterShape

    var body: some View {
        let tint = shape.used >= 0.9 ? Color.orange : Color.themeAccent
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Color.primary.opacity(0.1)
                tint.frame(width: width * shape.solid)
                Hatch().stroke(tint, lineWidth: 1).background(tint.opacity(0.3)).frame(width: width * shape.hatched).offset(x: width * shape.solid)
            }
            .clipShape(Capsule())
        }
        .frame(height: 4).accessibilityHidden(true)
    }
}

private struct Hatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 3
        }
        return path
    }
}
