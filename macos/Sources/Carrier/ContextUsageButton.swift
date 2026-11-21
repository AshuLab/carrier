import CarrierCore
import SwiftUI

/// The ring beside the microphone: how full the session's context is (the outer ring) and how much of the account's 5h limit is used (the
/// inner one), in the colors of the Usage page's bars (the theme's accent, orange from 90 %). A click opens what it counts, with the
/// Usage page's own meters.
struct ContextUsageButton: View {
    let context: ContextUse?
    /// The session's account, as `providers.json` names it: the limits are its own.
    let account: String
    let store: UsageStore
    /// Whether the agent is answering: its end asks the quotas again, since the turn spent some.
    let busy: Bool
    @State private var open = false

    private var usage: AccountUsage? { accountUsage(account, in: store.quotas, now: Int(Date().timeIntervalSince1970 * 1000)) }

    var body: some View {
        let usage = usage
        let words = contextRingWords(context: context, usage: usage)
        Button { open.toggle() } label: { EmptyView() }
            .buttonStyle(ContextRingStyle(context: context?.share, limit: usage?.ringWindow?.shape.used, stale: usage?.stale == true))
            .help(words)
            .accessibilityLabel("Context and usage limits")
            .accessibilityValue(words)
            .popover(isPresented: $open, arrowEdge: .top) { ContextUsageDetail(context: context, account: account, store: store, usage: usage, close: { open = false }) }
            // asked when it appears, when a turn ends and when the popover opens, and never more than once a minute (the host's own)
            .task { await store.loadUnlessRecent() }
            .onChange(of: busy) { _, working in if working == false { Task { await store.loadUnlessRecent() } } }
            .onChange(of: open) { _, now in if now { Task { await store.loadUnlessRecent() } } }
    }
}

/// The ring in the microphone's 36 point frame and its round hover, so the two sit as one pair.
private struct ContextRingStyle: ButtonStyle {
    let context: Double?
    let limit: Double?
    let stale: Bool

    func makeBody(configuration: Configuration) -> some View { Face(context: context, limit: limit, stale: stale, pressed: configuration.isPressed) }

    struct Face: View {
        let context: Double?
        let limit: Double?
        let stale: Bool
        let pressed: Bool
        @State private var hovering = false

        var body: some View {
            ZStack {
                Ring(share: context, diameter: 20)
                // what the last check said stays, dimmer, while a later one was refused: the detail says it is stale
                Ring(share: limit, diameter: 12).opacity(stale ? 0.5 : 1)
            }
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.secondary.opacity(pressed ? 0.2 : hovering ? 0.14 : 0)))
            .contentShape(Circle())
            .contentShape(.focusEffect, Circle())
            .onHover { hovering = $0 }
        }
    }
}

/// One ring: a track and the share of it in the accent, orange from 90 % as the Usage page's bars are. No share (not known yet) is the track alone.
private struct Ring: View {
    let share: Double?
    let diameter: CGFloat
    private let width: CGFloat = 2

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: width)
            if let share {
                Circle().trim(from: 0, to: max(share, 0.02))
                    .stroke(share >= 0.9 ? Color.orange : Color.themeAccent, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.25), value: share)
    }
}

/// What the ring counts: the context with its tokens, then the account's meters (the Providers page's own `AccountUsageMeters`), then the way to
/// the Usage page. The popover is the system's, which is glass on its own.
private struct ContextUsageDetail: View {
    let context: ContextUse?
    let account: String
    let store: UsageStore
    let usage: AccountUsage?
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let context {
                VStack(alignment: .leading, spacing: 3) {
                    if let share = context.share { UsageMeterLine(label: "Context", shape: MeterShape(solid: share)) }
                    Text(context.text + (context.share == nil ? " context" : "")).font(.scaled(10.5)).foregroundStyle(.secondary)
                        .padding(.leading, context.share == nil ? 0 : 54)
                }
            } else {
                Text("The context is known after the first answer.").font(.scaled(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            SettingsDivider()
            if let usage {
                AccountUsageMeters(usage: usage)
            } else {
                Text(limitsWords).font(.scaled(11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            SettingsDivider()
            HStack {
                Spacer(minLength: 0)
                Button("Open Usage") { close(); WindowController.shared.showUsage() }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
        }
        .padding(14).frame(width: 290)
    }

    /// Why there are no meters: the account is signed out, the check is still on its way, or the account has no limits to tell (a local server).
    private var limitsWords: String {
        // an ask that failed (a host too old for `usage`, one that did not answer) is not "still checking": Usage says why
        if let quota = store.quotas.first(where: { $0.account == account }) {
            return quota.status == .signedOut ? "\(quota.displayName ?? account) is signed out." : "No limits to show for this account."
        }
        if store.error != nil { return "The limits could not be read. Open Usage to see why." }
        return store.isLoading || store.snapshot == nil ? "Checking the limits…" : "No limits to show for this account."
    }
}
