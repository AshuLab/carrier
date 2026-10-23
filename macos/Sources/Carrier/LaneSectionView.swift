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
            .padding(.horizontal, 12).padding(.vertical, 4)
            .sessionRow()
        if open {
            TranscriptRows(content: .items(lane.items), outputs: $outputs)
        }
    }
}

struct LaneHeaderView: View {
    let lane: LaneSection
    let open: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: "chart.pie.fill").font(.system(size: 14)).foregroundStyle(tint)
                    .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.22)))
                HStack(spacing: 7) {
                    if let slice = lane.slice { Text("#\(slice)").foregroundStyle(.secondary) }
                    Text(lane.title)
                }
                .fontWeight(.semibold).lineLimit(1)
                Spacer(minLength: 8)
                if let duration = lane.duration { Text(formatDuration(duration)).font(.caption).foregroundStyle(.secondary) }
                state
                // the round button of the session's header
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.secondary.opacity(0.16)))
            }
            // the pull request is always there, so the row keeps its height with no lane
            HStack(spacing: 8) {
                CountPills(counts: lane.counts)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    if let number = lane.laneNumber {
                        Text("Lane \(number) ≈").help("Inferred from the worktree name; the agent does not report it")
                    }
                    Text(lane.pullRequest)
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.leading, 36)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
    }

    private var tint: Color { lane.state == .failed ? .red : .blue }

    @ViewBuilder private var state: some View {
        switch lane.state {
        case .running: ProgressView().controlSize(.small).frame(width: 16, height: 16)
        case .finished: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).frame(width: 16, height: 16)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red).frame(width: 16, height: 16)
        }
    }
}
