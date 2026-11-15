import AppKit
import CarrierCore
import SwiftUI

// A slice of the epic as a work card, where it was taken (docs/macos-ui.md, "The slice card"; the mockup is S1 of
// docs/research/macos-app-design/explorations/carrier-view-cards.html): its mark, `#730` and the title, a quiet line and its pull request.

/// The epic's repository ("owner/name"), so a pull request chip can open GitHub; without it the chip is a label. Set once on the view
/// that holds the transcript.
private struct EpicRepoKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    var epicRepo: String? {
        get { self[EpicRepoKey.self] }
        set { self[EpicRepoKey.self] = newValue }
    }
}

/// Opens or folds a part of a card. The change is animated here, where it is made, as the tool group does (a lazy feed moves what is
/// under a card smoothly only when the whole update is in the transaction).
func flipCard(_ change: () -> Void) {
    withAnimation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .smooth(duration: 0.3), change)
}

/// The chevron at the right of a card's line or row: right when folded, down when open.
struct CardChevron: View {
    let open: Bool
    var width: CGFloat = 16

    var body: some View {
        Image(systemName: "chevron.right").font(.scaled(9, weight: .bold)).foregroundStyle(.tertiary)
            .rotationEffect(.degrees(open ? 90 : 0)).frame(width: width).accessibilityHidden(true)
    }
}

/// "PR #736" with a dot for its state and an arrow when it opens GitHub; a link when it has a url.
struct PullRequestChip: View {
    let number: Int
    let dot: Color?
    let url: String?

    var body: some View {
        if let link = url.flatMap(browserURL) {
            Link(destination: link) { label }.buttonStyle(.plain).help(link.absoluteString)
        } else {
            label
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            Text("PR #\(number)").monospacedDigit()
            if url != nil { Image(systemName: "arrow.up.right").font(.scaled(9, weight: .semibold)).foregroundStyle(.tertiary) }
        }
        .font(.scaled(12)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
    }
}

extension SlicePRState {
    /// The mockup's: merged purple, open green, draft grey; closed without merging is red and a pull request of unknown state is grey.
    var dot: Color {
        switch self {
        case .merged: .purple
        case .open: .green
        case .draft, .unknown: Color.secondary.opacity(0.6)
        case .closed: .red
        }
    }
}

struct SliceCardView: View {
    /// The subagent of the slice.
    let lane: LaneSection
    /// What the person opened in the transcript's work cards, shared by the whole tab.
    @Binding var flipped: Set<String>
    /// What the person flipped: the row from how it starts (open while the slice works).
    @Binding var slices: SliceFolds
    @Environment(\.epicRepo) private var repo
    @AppStorage(AppPreferences.toolOutputKey) private var mode = AppPreferences.defaultToolOutput
    @AppStorage(AppPreferences.showsReasoningKey) private var showsReasoning = AppPreferences.defaultShowsReasoning

    var body: some View {
        let row = sliceCard(lane: lane)
        let open = row.openByDefault != slices.isOpen(row.id)
        SliceCardRowView(row: row, open: open, prURL: prURL(row), toggle: { flipCard { slices.toggle(row.id) } }) {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(visibleFlow(flowItems(lane.items, running: lane.state == .running), mode: mode, showsReasoning: showsReasoning)) { FlowItemView(flow: $0, flipped: $flipped, slices: $slices) }
            }
            // under the title: the mark's column and gap, less the 12 pt a row of the log has of its own
            .padding(.leading, 33).padding(.top, 8).padding(.bottom, 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .workCard()
    }

    private func prURL(_ row: SliceCardRow) -> String? {
        guard let repo, let number = row.prNumber else { return nil }
        return "https://github.com/\(repo)/pull/\(number)"
    }
}

/// A slice: its mark, `#730` and the title, the quiet line under it, and at the right the pull request and the chevron. The row is a
/// button, away from the chip, and opens to the slice's own steps.
private struct SliceCardRowView<Opened: View>: View {
    let row: SliceCardRow
    let open: Bool
    let prURL: String?
    let toggle: () -> Void
    @ViewBuilder let opened: () -> Opened
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Button(action: toggle) {
                    HStack(alignment: .top, spacing: 11) {
                        mark.frame(width: 22, height: 18, alignment: .leading).padding(.top, 1).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            title.font(.scaled(13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                            quiet
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, 12).padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.spoken + (open ? ", open" : ", closed"))
                if let number = row.prNumber { PullRequestChip(number: number, dot: row.prState.dot, url: prURL).padding(.top, 11).padding(.leading, 10) }
                // the chevron is the same click, away from the chip; the row's button is the one the keyboard reaches
                Button(action: toggle) {
                    CardChevron(open: open, width: 12).padding(.leading, 10).padding(.trailing, 12).padding(.top, 11).padding(.bottom, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false).accessibilityHidden(true)
            }
            .background(Color.primary.opacity(hovered ? 0.04 : 0))
            .onHover { hovered = $0 }
            if open { opened() }
        }
    }

    private var title: Text {
        guard let number = row.number else { return Text(row.title) }
        return Text("\(Text("#\(number)").foregroundStyle(.tertiary).fontWeight(.medium))  \(Text(row.title))")
    }

    private var quiet: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(row.quiet.enumerated()), id: \.offset) { index, part in
                if index > 0 { Text("·").foregroundStyle(.tertiary) }
                switch part.kind {
                case .plain: Text(part.text)
                case .error: Text(part.text).foregroundStyle(.red)
                case .lane:
                    Text(part.text).font(.scaled(10.5, weight: .semibold)).padding(.horizontal, 7)
                        .background(Capsule().fill(Color.primary.opacity(0.1))).help("The lane the agent worked in, read from its worktree")
                }
            }
        }
        .font(.scaled(12)).foregroundStyle(.secondary)
    }

    @ViewBuilder private var mark: some View {
        switch row.mark {
        case .done: Disc(color: .green, mark: "✓", shape: .ready, size: 18)
        case .working: SpinningRing(diameter: 18, lineWidth: 2.5, color: .systemGreen)
        case .failed: Disc(color: .red, mark: "!", shape: .problem, size: 18)
        }
    }
}
