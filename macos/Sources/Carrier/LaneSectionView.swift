import CarrierCore
import SwiftUI

/// A subagent of a session in the log, where it was taken: a row of two lines that opens in place on the subagent's own rows.
/// Closed by default whatever its state; what the user opened is kept per subagent. Read-only, with no resume button: Continue in
/// Terminal under the session resumes the whole thing. Open, the rows hang 24 pt in behind a 1.5 pt rule under the state glyph's
/// centre (x = 19), so their icons start under the title.
struct LaneSectionView: View {
    let lane: LaneSection
    @Binding var outputs: OutputFolds
    @Binding var groups: GroupFolds
    @Binding var slices: SliceFolds

    var body: some View {
        let open = slices.isOpen(lane.id)
        VStack(alignment: .leading, spacing: 0) {
            Button { slices.toggle(lane.id) } label: { LaneHeaderView(lane: lane, open: open) }
                .buttonStyle(.plain)
            if open {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(flowItems(lane.items)) { FlowItemView(flow: $0, outputs: $outputs, groups: $groups, slices: $slices) }
                }
                .thread(indent: LogMetrics.sliceIndent, rule: LogMetrics.sliceRule, tint: lane.threadTint)
            }
        }
    }
}

/// The two lines of a slice row, with no surface: the state, `#N` and the title, and the chevron of a call's column; under the
/// title the count pills and the meta items. Hover tints both lines.
struct LaneHeaderView: View {
    let lane: LaneSection
    let open: Bool
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: LogMetrics.gap) {
                // keeps the title in its column; the state is drawn centred on both lines below
                Color.clear.frame(width: LogMetrics.iconWidth, height: 1)
                HStack(spacing: 5) {
                    if let slice = lane.slice { Text("#\(slice)").fontWeight(.medium).foregroundStyle(.secondary) }
                    Text(lane.title).fontWeight(.semibold)
                }
                .font(.system(size: 12)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                // keeps the title short of the chevron, which is drawn centred on both lines below
                Color.clear.frame(width: LogMetrics.chevronColumn, height: 1)
            }
            .frame(height: LogMetrics.sliceLine)
            HStack(spacing: 8) {
                if starting == false { CountPills(counts: lane.counts) }
                meta.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.leading, LogMetrics.titleColumn - LogMetrics.iconColumn)
            .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
            .padding(.bottom, 8)
        }
        .overlay(alignment: .leading) { state.frame(width: LogMetrics.iconWidth, height: LogMetrics.iconWidth) }
        .overlay(alignment: .trailing) { LogChevron(open: open) }
        .padding(.horizontal, LogMetrics.iconColumn)
        .rowHover(hovered)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(laneAccessibilityLabel(lane, open: open))
    }

    private var starting: Bool { lane.isStarting }

    /// The items of line two, split by " · ".
    private var meta: Text {
        var items: [Text] = []
        if lane.state == .failed { items.append(Text("did not complete").foregroundStyle(.red)) }
        if starting {
            items.append(Text("starting…"))
        } else {
            if let number = lane.laneNumber { items.append(Text("Lane \(number) ≈")) }
            items.append(pullRequest)
            if let timeLabel = lane.timeLabel { items.append(Text(timeLabel)) }
            if let resumed = lane.resumedLabel { items.append(Text(resumed)) }
        }
        return items.dropFirst().reduce(items[0]) { $0 + Text(" · ") + $1 }
    }

    private var pullRequest: Text {
        guard lane.pullRequest.hasSuffix(" merged") else { return Text(lane.pullRequest) }
        return Text(lane.pullRequest.dropLast(" merged".count)) + Text(" merged").foregroundStyle(.green)
    }

    @ViewBuilder private var state: some View {
        switch lane.state {
        case .running: SpinningRing(diameter: 14, lineWidth: 2, color: .secondaryLabelColor).accessibilityHidden(true)
        case .finished: Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.red)
        }
    }
}

private extension LaneSection {
    /// The colour of the thread's rule while hovered: the state glyph's.
    var threadTint: Color {
        switch state {
        case .finished: .green
        case .failed: .red
        case .running: .secondary
        }
    }
}
