import CarrierCore
import SwiftUI

/// The card that opens beside a Carrier row when the pointer rests on it: who the epic is, the steps with the one in hand filled, the facts
/// of where it stands and when it happened. Nothing in it takes a click yet, but the pointer can enter it and keep it open, so what is
/// added later (a button, a link) works.
struct EpicCardView: View {
    let card: EpicCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ProjectIcon(name: card.name, colorKey: projectColorKey(card.name))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title).font(.scaled(14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(card.subtitle).font(SidebarMetrics.detail).foregroundStyle(.secondary)
                }
            }
            if card.steps.isEmpty == false {
                HStack(spacing: 6) {
                    ForEach(card.steps.indices, id: \.self) { StepBar(step: card.steps[$0]) }
                }
            }
            if card.facts.isEmpty == false {
                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 5) {
                    ForEach(card.facts.indices, id: \.self) { index in
                        GridRow {
                            Text(card.facts[index].label).foregroundStyle(.secondary)
                            Text(card.facts[index].value).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(SidebarMetrics.detail)
            }
            if let timeline = card.timeline {
                Text(timeline).font(.scaled(11.5)).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }
}

/// One step: a bar (green when done, blue while in hand, orange or red when it is stuck) filled as far as it is known, and its name.
private struct StepBar: View {
    let step: EpicCard.Step

    private var color: Color {
        switch step.state {
        case .done: .green
        case .current: .blue
        case .input: .orange
        case .error: .red
        case .waiting, .cancelled: .secondary
        }
    }

    private var held: Bool { [.current, .input, .error].contains(step.state) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Capsule().fill(Color.primary.opacity(0.14)).frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        switch step.state {
                        case .done: Capsule().fill(color)
                        case .current, .input, .error:
                            // a step with no count is drawn whole but faint: nothing says how far it is
                            Capsule().fill(color.opacity(step.progress == nil ? 0.55 : 1)).frame(width: proxy.size.width * (step.progress ?? 1))
                        case .waiting, .cancelled: EmptyView()
                        }
                    }
                }
            Text(step.name).font(.scaled(11, weight: held ? .semibold : .regular)).foregroundStyle(held ? .primary : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
