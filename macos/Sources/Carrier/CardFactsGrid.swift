import CarrierCore
import SwiftUI

/// The facts of a card that opens on a row (`SessionPeekView`, `EpicCardView`): a quiet label and a value drawn by its kind. A path or a
/// branch is one line cut in the middle, with the whole of it in its tooltip and selectable to copy, so a long one never breaks over four
/// lines; an agent is its account's mark and short name.
struct CardFactsGrid: View {
    let facts: [CardFact]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            ForEach(facts.indices, id: \.self) { index in
                GridRow(alignment: .firstTextBaseline) {
                    Text(facts[index].label).foregroundStyle(.secondary)
                    value(facts[index]).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(SidebarMetrics.detail)
    }

    @ViewBuilder private func value(_ fact: CardFact) -> some View {
        switch fact.kind {
        case .text:
            Text(fact.value).fixedSize(horizontal: false, vertical: true)
        case .path:
            Text(fact.value).font(.scaled(10.5, design: .monospaced)).lineLimit(1).truncationMode(.middle).help(fact.value).textSelection(.enabled)
        case .branch:
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch").font(.scaled(10)).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(fact.value).font(.scaled(10.5, design: .monospaced)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            .help(fact.value)
        case .agent:
            HStack(spacing: 5) {
                AccountMark(account: fact.value, size: 12).accessibilityHidden(true)
                Text(ProviderIdentityStore.shared.shortName(of: fact.value)).lineLimit(1)
            }
            .help(fact.value)
        }
    }
}
