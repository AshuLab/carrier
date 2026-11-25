import CarrierCore
import SwiftUI

/// The Details tab: the four groups of rows, each a card with its title in capitals above it. A row is an icon, a label with its
/// note and the value at the far end; a value too long for that (a branch name) goes under the label.
struct DetailsTabView: View {
    private let timeChanges = TimeFormatChanges()
    let subject: EpicSubject?
    let reply: EpicReply?
    let sessions: SessionsReply?

    var body: some View {
        let model = detailsTab(subject, reply: reply, sessions: sessions, now: Int(Date().timeIntervalSince1970 * 1000))
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s22) {
                ForEach(model.groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                        // in line with the rows' content, which the card pads by 14
                        Text(group.title).textCase(.uppercase).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, Tokens.Space.s14)
                        OverviewCard {
                            ForEach(group.rows, id: \.label) { DetailsRowView(row: $0) }
                        }
                    }
                }
            }
            .padding(.top, Tokens.Space.s6).padding(.bottom, Tokens.Space.s12)
        }
    }
}

struct DetailsRowView: View {
    @Environment(\.pieceTheme) private var theme
    let row: DetailsRow

    /// Past this many characters a value goes under its label.
    private static let longValue = 26

    var body: some View {
        let stacked = row.value.count > Self.longValue
        HStack(alignment: stacked ? .top : .firstTextBaseline, spacing: Tokens.Space.s10) {
            Glyph(row.icon, size: 12).foregroundStyle(.secondary).frame(width: 18)
            if stacked {
                VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                    label
                    value.font(.caption.monospaced())
                }
            } else {
                label
                Spacer(minLength: 8)
                value.multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, Tokens.Space.s10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
            Text(row.label).font(.callout.weight(.medium))
            if let note = row.note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private var value: some View {
        let color: Color = switch row.tone {
        case .normal: .primary
        case .good: .green
        case .attention: .orange
        case .bad: .red
        case .dim: .secondary
        }
        let link = row.url.flatMap(browserURL)
        switch row.style {
        case .badge:
            if let link {
                Link(destination: link) { DetailsBadge(text: row.value, color: row.tone == .normal ? theme.accent : color, linked: true) }
                    .buttonStyle(.plain).help(link.absoluteString)
            } else {
                DetailsBadge(text: row.value, color: color, linked: false)
            }
        case .text:
            Text(row.value).font(.callout.monospacedDigit()).foregroundStyle(color)
        }
    }
}

/// A value as a capsule of its colour; a link has an arrow after the text. A neutral one is grey with the text at full strength.
private struct DetailsBadge: View {
    let text: String
    let color: Color
    let linked: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.s4) {
            Text(text).lineLimit(1).truncationMode(.middle)
            if linked { Glyph(.arrowUpRight, size: 9) }
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(color)
        .padding(.horizontal, Tokens.Space.s10).padding(.vertical, Tokens.Space.s3)
        .background(Capsule().fill(color == .primary ? Color.secondary.opacity(0.16) : color.opacity(0.18)))
    }
}

private extension DetailsRow {
    /// An SF Symbol for the row, by what it says; a plain dot for one this app does not know.
    var icon: AppIcon {
        switch field {
        case .stage: .flag
        case .lastActivity: .activity
        case .started: .calendar
        case .totalTime: .timer
        case .slices: .stack
        case .reviewRound: .refresh
        case .blockers: .hand
        case .pullRequest: .gitPullRequest
        case .checks: .shieldCheck
        case .branch: .gitBranch
        case .agent: .cpu
        case .lanes: .layoutGrid
        case .repository: .package
        case .other: .circleFilled
        }
    }
}
