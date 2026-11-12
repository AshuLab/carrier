import CarrierCore
import SwiftUI

/// The card that opens beside a session's row when the pointer rests on it, like an epic's (`EpicCardView`): the whole title, the last
/// thing the agent wrote, the facts of where it works and when it last moved.
struct SessionPeekView: View {
    let card: SessionPeek

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ProjectIcon(name: card.name, colorKey: projectColorKey(card.name))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title).font(.scaled(14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(card.subtitle).font(SidebarMetrics.detail).foregroundStyle(.secondary)
                }
            }
            if let message = card.lastMessage {
                Text(message).font(SidebarMetrics.detail).foregroundStyle(.secondary).lineLimit(4)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            }
            Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(card.facts.indices, id: \.self) { index in
                    GridRow {
                        Text(card.facts[index].label).foregroundStyle(.secondary)
                        Text(card.facts[index].value).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(SidebarMetrics.detail)
            Text(card.timeline).font(.scaled(11.5)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }
}
