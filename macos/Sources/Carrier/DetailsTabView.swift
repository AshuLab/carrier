import CarrierCore
import SwiftUI

/// The Details tab: the four groups of rows, a label with its note on the left and the value on the right.
struct DetailsTabView: View {
    let subject: EpicSubject?
    let reply: EpicReply?

    var body: some View {
        let model = detailsTab(subject, reply: reply, now: Int(Date().timeIntervalSince1970 * 1000))
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(model.groups, id: \.title) { group in
                    Text(group.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
                    VStack(spacing: 0) {
                        ForEach(group.rows, id: \.label) { DetailsRowView(row: $0) }
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.07)))
                }
            }
        }
    }
}

struct DetailsRowView: View {
    let row: DetailsRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.label).font(.callout.weight(.medium))
                if let note = row.note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            value.multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var value: some View {
        let color: Color = switch row.tone {
        case .normal: .primary
        case .good: .green
        case .attention: .orange
        case .bad: .red
        case .dim: .secondary
        }
        if let link = row.url.flatMap(browserURL) {
            Link(row.value + " ↗", destination: link).font(.callout.monospacedDigit())
        } else {
            Text(row.value).font(.callout.monospacedDigit()).foregroundStyle(color)
        }
    }
}
