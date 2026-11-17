import CarrierCore
import SwiftUI

/// The card that opens beside a session's row when the pointer rests on it, like an epic's (`EpicCardView`): the whole title, the last
/// thing the agent wrote, the facts of where it works and when it last moved.
struct SessionPeekView: View {
    let card: SessionPeek

    /// The violet of the ring for work in hand, deeper on light, where the ring's own pale one has about 2:1 against the card.
    private static let working = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.79, green: 0.63, blue: 1.0, alpha: 1) : NSColor(red: 0.42, green: 0.22, blue: 0.72, alpha: 1)
    })

    /// The colours of the row's own words: orange for what needs the person, green for Done, violet for work in hand.
    private var tone: Color {
        switch card.tone {
        case .quiet: .secondary
        case .working: Self.working
        case .attention: SessionRowView.attention
        case .done: SessionRowView.done
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ProjectIcon(name: card.name, colorKey: projectColorKey(card.name))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title).font(.scaled(14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(card.subtitle).font(SidebarMetrics.detail).fontWeight(card.tone == .quiet ? .regular : .medium).foregroundStyle(tone)
                }
            }
            if let message = card.lastMessage {
                Text(message).font(SidebarMetrics.detail).foregroundStyle(.secondary).lineLimit(4)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            }
            CardFactsGrid(facts: card.facts)
            Text(card.timeline).font(.scaled(11.5)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }
}
