import CarrierCore
import SwiftUI

/// The Overview's Running section; a thin mapping of `runningSection(_:)`. Clicking a card selects the epic.
struct RunningView: View {
    let snapshot: PanelSnapshot
    @Binding var selection: Selection

    var body: some View {
        let section = runningSection(snapshot)
        VStack(alignment: .leading, spacing: 8) {
            Text("RUNNING").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if section.cards.isEmpty {
                EmptyStateView(state: .idle).frame(height: 170)
            } else {
                ForEach(section.cards.indices, id: \.self) { card(section.cards[$0]) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.room.title).fontWeight(.semibold)
                    Text(section.room.line).font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
        }
    }

    private func card(_ card: RunningCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(card.title).font(.headline)
                Text(card.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if let progress = card.progress { ProgressView(value: progress).frame(maxWidth: 220) }
                Text(card.progressLine).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ForEach(card.agents.indices, id: \.self) { agent(card.agents[$0]) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        .contentShape(Rectangle())
        .onTapGesture { selection = card.selection }
    }

    private func agent(_ row: AgentRow) -> some View {
        HStack(spacing: 10) {
            RunningAvatar(initial: row.initial, running: row.running)
            VStack(alignment: .leading, spacing: 1) {
                Text([row.agent, row.role, row.round].compactMap { $0 }.joined(separator: " · ")).fontWeight(.medium)
                Text(row.action).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(row.since).font(.caption).foregroundStyle(.secondary)
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
            .overlay { if let ring { ring } }
    }
}
