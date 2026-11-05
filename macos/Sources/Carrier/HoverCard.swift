import CarrierCore
import SwiftUI

/// When a card last closed, shared by every row: the next one opens at once if it was a moment ago.
@MainActor private var lastCardClosedAt: Date?

extension View {
    /// Opens `card` beside the view when the pointer rests on it, keeps it while the pointer is on the view or on the card, and closes it
    /// a moment after it left both (`hoverCardStep`). A popover with an arrow, the system's own: the pointer can enter it and what is in it
    /// takes clicks.
    func hoverCard<Card: View>(@ViewBuilder _ card: @escaping () -> Card) -> some View {
        modifier(HoverCard(card: card))
    }
}

private struct HoverCard<Card: View>: ViewModifier {
    let card: () -> Card
    @State private var shown = false
    @State private var onRow = false
    @State private var onCard = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { onRow = $0; moved() }
            .popover(isPresented: $shown, arrowEdge: .trailing) {
                card().onHover { onCard = $0; moved() }
            }
    }

    private func moved() {
        pending?.cancel()
        switch hoverCardStep(onRow: onRow, onCard: onCard, shown: shown, closedAt: lastCardClosedAt, now: Date()) {
        case .open(let after):
            pending = Task {
                try? await Task.sleep(for: after)
                if Task.isCancelled == false { shown = true }
            }
        case .close(let after):
            pending = Task {
                try? await Task.sleep(for: after)
                guard Task.isCancelled == false else { return }
                shown = false
                lastCardClosedAt = Date()
            }
        case .keep: break
        }
    }
}
