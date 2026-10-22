import CarrierCore
import SwiftUI

/// The Details tab: the four groups of rows, each a card with its title in capitals above it. A row is an icon, a label with its
/// note and the value at the far end; a value too long for that (a branch name) goes under the label.
struct DetailsTabView: View {
    let subject: EpicSubject?
    let reply: EpicReply?

    var body: some View {
        let model = detailsTab(subject, reply: reply, now: Int(Date().timeIntervalSince1970 * 1000))
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(model.groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        // in line with the rows' content, which the card pads by 14
                        Text(group.title).textCase(.uppercase).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 14)
                        OverviewCard {
                            ForEach(group.rows, id: \.label) { DetailsRowView(row: $0) }
                        }
                    }
                }
            }
            .padding(.top, 6).padding(.bottom, 12)
        }
    }
}

struct DetailsRowView: View {
    let row: DetailsRow

    /// Past this many characters a value goes under its label.
    private static let longValue = 26

    var body: some View {
        let stacked = row.value.count > Self.longValue
        HStack(alignment: stacked ? .top : .firstTextBaseline, spacing: 10) {
            Image(systemName: row.icon).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(width: 18)
            if stacked {
                VStack(alignment: .leading, spacing: 3) {
                    label
                    value.font(.caption.monospaced())
                }
            } else {
                label
                Spacer(minLength: 8)
                value.multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 1) {
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
                Link(destination: link) { DetailsBadge(text: row.value, color: row.tone == .normal ? .accentColor : color, linked: true) }
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
        HStack(spacing: 4) {
            Text(text).lineLimit(1).truncationMode(.middle)
            if linked { Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)) }
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(Capsule().fill(color == .primary ? Color.secondary.opacity(0.16) : color.opacity(0.18)))
    }
}

private extension DetailsRow {
    /// An SF Symbol for the row, by its label; a plain dot for one this app does not know.
    var icon: String {
        switch label {
        case "Stage": "flag"
        case "Last activity": "waveform.path.ecg"
        case "Started": "calendar"
        case "Total time": "timer"
        case "Slices": "square.stack.3d.up"
        case "Review round": "arrow.triangle.2.circlepath"
        case "Blockers": "hand.raised"
        case "Pull request": "arrow.triangle.pull"
        case "Checks": "checkmark.shield"
        case "Branch": "arrow.triangle.branch"
        case "Agent": "cpu"
        case "Lanes": "rectangle.3.group"
        case "Repository": "shippingbox"
        default: "circle.fill"
        }
    }
}
