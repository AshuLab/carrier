import CarrierCore
import CarrierUI
import SwiftUI

extension CardFactsGrid.Fact {
    /// The line of a card's facts as the grid draws it; an agent's is its account's mark and short name, as the store has them.
    @MainActor init(_ fact: CardFact) {
        let kind: Kind =
            switch fact.kind {
            case .text: .text
            case .path: .path
            case .branch: .branch
            case .agent: .account(mark: AccountMark(account: fact.value, size: 12), name: ProviderIdentityStore.shared.shortName(of: fact.value))
            }
        self.init(label: fact.label, value: fact.value, kind: kind, detail: fact.detail)
    }
}

extension CardFactsGrid {
    @MainActor init(facts: [CardFact], @ViewBuilder extra: @escaping () -> Extra) { self.init(facts: facts.map(Fact.init), extra: extra) }
}

extension CardFactsGrid where Extra == EmptyView {
    @MainActor init(facts: [CardFact]) { self.init(facts: facts.map(Fact.init)) }
}
