import AppKit
import CarrierCore
import SwiftUI

// What the Providers page draws its rows with: an account's row and its meters, a state as words, and the avatars of a provider and an account.

/// An account of a provider, with its own usage: its name and state, who uses it and where its login lives and, at the right, its 5h and Weekly
/// meters with when they reset (or Sign in, for a signed-out one). When that does not fit (a narrow window, the largest text) the meters go under
/// the text. The whole row opens the account; the buttons inside keep their own clicks.
struct AccountRow: View {
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
struct StateWords: View {
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
struct ProviderTile: View {
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
struct AccountTile: View {
    let account: String
    let icon: String

    var body: some View {
        AccountMark(account: account, icon: icon, size: 22)
            .frame(width: 38, height: 38).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07)))
            .accessibilityHidden(true)
    }
}

/// An account's state: a dot of its colour and the words, orange for what asks for an action.
struct AccountStateLabel: View {
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
