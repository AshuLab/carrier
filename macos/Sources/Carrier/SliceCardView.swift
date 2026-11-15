import AppKit
import CarrierCore
import SwiftUI

// The epic's slices as one work card (docs/macos-ui.md, "The slices card"; the mockup is S1 of
// docs/research/macos-app-design/explorations/carrier-view-cards.html): a 30 pt line with the count of merged slices and a row per slice.

/// The epic's repository ("owner/name"), so a pull request chip can open GitHub; without it the chip is a label. Set once on the view
/// that holds the transcript.
private struct EpicRepoKey: EnvironmentKey { static let defaultValue: String? = nil }

extension EnvironmentValues {
    var epicRepo: String? {
        get { self[EpicRepoKey.self] }
        set { self[EpicRepoKey.self] = newValue }
    }
}

/// The epic's slices that have not started, while the builder runs; the slices card lists them after the ones that did.
private struct WaitingSlicesKey: EnvironmentKey { static let defaultValue: [EpicReply.Slice] = [] }

extension EnvironmentValues {
    var waitingSlices: [EpicReply.Slice] {
        get { self[WaitingSlicesKey.self] }
        set { self[WaitingSlicesKey.self] = newValue }
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
    /// The session's subagents in order;.
    let lanes: [LaneSection]
    /// The epic's slices that have not started, while the builder runs.
    var waiting: [EpicReply.Slice] = []
    /// What the person opened in the transcript's work cards, shared by the whole tab.
    @Binding var flipped: Set<String>
    /// What the person flipped: a row from how it starts (the first one is open while it works), the card from open.
    @Binding var slices: SliceFolds
    @Environment(\.epicRepo) private var repo
    @AppStorage(AppPreferences.toolOutputKey) private var mode = AppPreferences.defaultToolOutput
    @AppStorage(AppPreferences.showsReasoningKey) private var showsReasoning = AppPreferences.defaultShowsReasoning

    var body: some View {
        let card = sliceCard(lanes: lanes, waiting: waiting)
        let folded = slices.isOpen(cardKey)
        VStack(alignment: .leading, spacing: 0) {
            Button { flipCard { slices.toggle(cardKey) } } label: { header(card, open: folded == false) }
                .buttonStyle(.plain)
                .accessibilityLabel("Slices, \(card.summary)")
                .accessibilityHint(folded ? "Shows the slices" : "Hides the slices")
            if folded == false {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(card.rows) { row in
                        let open = row.canOpen && row.openByDefault != slices.isOpen(row.id)
                        SettingsDivider()
                        SliceCardRowView(row: row, open: open, prURL: prURL(row), toggle: { flipCard { slices.toggle(row.id) } }) {
                            if let lane = row.lane {
                                VStack(alignment: .leading, spacing: 9) {
                                    ForEach(visibleFlow(flowItems(lane.items, running: lane.state == .running), mode: mode, showsReasoning: showsReasoning)) { FlowItemView(flow: $0, flipped: $flipped, slices: $slices) }
                                }
                                // under the title: the mark's column and gap, less the 12 pt a row of the log has of its own
                                .padding(.leading, 33).padding(.top, 8).padding(.bottom, 6)
                            }
                        }
                    }
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
            }
        }
        .workCard()
    }

    /// The card's own fold is kept with the rows', under a key no subagent has.
    private var cardKey: String { "slices-card/\(lanes.first?.id ?? "")" }

    private func prURL(_ row: SliceCardRow) -> String? {
        guard let repo, let number = row.prNumber else { return nil }
        return "https://github.com/\(repo)/pull/\(number)"
    }

    private func header(_ card: SliceCard, open: Bool) -> some View {
        HStack(spacing: 8) {
            lead(card.lead).frame(width: 16, height: 16)
            Text("Slices").fontWeight(.semibold)
            Text(card.summary).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 3) {
                ForEach(Array(card.segments.enumerated()), id: \.offset) { Capsule().fill(segment($0.element)).frame(width: 14, height: 4) }
            }
            .accessibilityHidden(true)
            Spacer(minLength: 8)
            if let time = card.time { Text(time).font(.scaled(12)).foregroundStyle(.tertiary).monospacedDigit().lineLimit(1) }
            CardChevron(open: open)
        }
        .font(.scaled(12.5))
        .padding(.horizontal, 10).frame(height: 30)
        .contentShape(Rectangle())
    }

    @ViewBuilder private func lead(_ lead: SliceLead) -> some View {
        switch lead {
        case .done: Disc(color: .green, mark: "✓", shape: .ready, size: 16)
        case .working: SpinningRing(diameter: 14, lineWidth: 2, color: .systemGreen).accessibilityHidden(true)
        case .waiting: Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5).frame(width: 14, height: 14)
        case .failed: Disc(color: .red, mark: "!", shape: .problem, size: 16)
        }
    }

    private func segment(_ mark: SliceMark) -> Color {
        switch mark {
        case .done: .green
        case .working: Color.green.opacity(0.5)
        case .failed: .red
        case .waiting: Color.primary.opacity(0.12)
        }
    }
}

/// A slice: its mark, `#730` and the title, the quiet line under it, and at the right the pull request and the chevron. A tap on
/// the row, away from the chip, opens it to the slice's own steps.
private struct SliceCardRowView<Opened: View>: View {
    let row: SliceCardRow
    let open: Bool
    let prURL: String?
    let toggle: () -> Void
    @ViewBuilder let opened: () -> Opened
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                mark.frame(width: 22, height: 18, alignment: .leading).padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    title.font(.scaled(13, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    quiet
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.spoken + (row.canOpen ? (open ? ", open" : ", closed") : ""))
                .accessibilityAddTraits(row.canOpen ? .isButton : [])
                .accessibilityAction(.default) { if row.canOpen { toggle() } }
                HStack(spacing: 10) {
                    if let number = row.prNumber { PullRequestChip(number: number, dot: row.prState.dot, url: prURL) }
                    CardChevron(open: open, width: 12).opacity(row.canOpen ? 1 : 0)
                }
                .padding(.top, 1)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { if row.canOpen { toggle() } }
            .background(Color.primary.opacity(hovered && row.canOpen ? 0.04 : 0))
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
        case .waiting: Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1.5).frame(width: 18, height: 18)
        case .failed: Disc(color: .red, mark: "!", shape: .problem, size: 18)
        }
    }
}
