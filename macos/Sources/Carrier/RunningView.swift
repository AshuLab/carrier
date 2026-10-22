import CarrierCore
import SwiftUI

/// The Overview's Running section; a thin mapping of `runningSection(_:)`. Clicking a card selects the epic.
struct RunningView: View {
    let snapshot: PanelSnapshot
    @Binding var selection: Selection

    var body: some View {
        let section = runningSection(snapshot)
        VStack(alignment: .leading, spacing: 8) {
            OverviewTitle(title: "Running", detail: "\(snapshot.slots.busy) of \(snapshot.slots.total) in use")
            if section.cards.isEmpty {
                OverviewCard { EmptyStateView(state: .idle).frame(height: 170) }
            } else {
                ForEach(section.cards.indices, id: \.self) { card(section.cards[$0]) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.room.title).fontWeight(.semibold)
                    Text(section.room.line).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
        }
    }

    /// One epic: its line and progress on top, a row for each of its agents under it. The first row opens the epic.
    private func card(_ card: RunningCard) -> some View {
        OverviewCard(fullWidthDividers: true) {
            OverviewLinkRow(action: { selection = card.selection }) {
                StateGlyph(state: .running).frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.title).fontWeight(.semibold)
                    Text(card.progressLine).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if let progress = card.progress {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(Int((progress * 100).rounded()))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        ProgressView(value: progress).tint(.green).frame(width: 90)
                    }
                }
            }
            ForEach(card.agents.indices, id: \.self) { agent(card.agents[$0]) }
        }
    }

    /// A child of the epic's row above it, so no chevron: its avatar lines up under the epic's icon.
    private func agent(_ row: AgentRow) -> some View {
        OverviewLinkRow {
            RunningAvatar(initial: row.initial, running: row.running)
            VStack(alignment: .leading, spacing: 1) {
                Text([row.agent, row.role, row.round].compactMap { $0 }.joined(separator: " · ")).fontWeight(.medium)
                Text(row.action).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(row.since).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
    }
}

/// A grey disc with the agent's letter; a white ring turns over it while the session runs, none when it does not.
struct RunningAvatar: View {
    let initial: String
    let running: Bool

    /// The ring over the disc; nil when the session is not running.
    var ring: SpinningRing? { running ? SpinningRing(diameter: 22, lineWidth: 2, color: .white) : nil }

    var body: some View {
        Text(initial).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.gray))
            .overlay { if let ring { ring.frame(width: 28, height: 28) } }
    }
}
