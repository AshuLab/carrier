import CarrierCore
import SwiftUI

/// A subagent of a session under its transcript: a header that folds its rows. Read-only, with no resume button: Continue in
/// Terminal under the session resumes the whole thing. Its rows go straight into the Agent output tab's lazy stack.
struct LaneSectionView: View {
    let lane: LaneSection
    @Binding var outputs: OutputFolds
    @State private var open = true

    var body: some View {
        Button { open.toggle() } label: { LaneHeaderView(lane: lane, open: open) }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
        if open {
            TranscriptRows(content: .items(lane.items), outputs: $outputs).padding(.leading, 16)
        }
    }
}

struct LaneHeaderView: View {
    let lane: LaneSection
    let open: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                .rotationEffect(.degrees(open ? 90 : 0))
            Text(lane.title).fontWeight(.semibold).lineLimit(1)
            if lane.hint {
                Text("hint").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.secondary.opacity(0.16)))
                    .help("Read from the agent's description and worktree name, not reported by the agent: it can be wrong.")
            }
            Spacer(minLength: 8)
            Text(lane.counts).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
