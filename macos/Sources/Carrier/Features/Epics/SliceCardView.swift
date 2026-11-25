import AppKit
import CarrierCore
import SwiftUI

// A slice of the epic as a work card, where it was taken (docs/ui.md, "The slice card"; the mockup is S1 of
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

extension PullRequestChip {
    /// The chip of a pull request that may open `url` on GitHub: a link when it is one the browser may open (`browserURL`), else a label.
    init(number: Int, dot: Color?, url: String?) { self.init(number: number, dot: dot, link: url.flatMap(browserURL)) }
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
    @Environment(\.epicRepo) private var repo
    @Environment(\.openSubagent) private var open

    var body: some View {
        let row = sliceCard(lane: lane)
        SliceCardRowView(row: row, prURL: prURL(row), open: { open?(lane.id) })
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
            .workCard()
    }

    private func prURL(_ row: SliceCardRow) -> String? {
        guard let repo, let number = row.prNumber else { return nil }
        return "https://github.com/\(repo)/pull/\(number)"
    }
}

/// A slice: its mark, `#730` and the title, the quiet line under it, and at the right the pull request and the chevron. The row is a
/// button, away from the chip, and opens the subagent's view.
private struct SliceCardRowView: View {
    let row: SliceCardRow
    let prURL: String?
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.none) {
            Button(action: open) {
                HStack(alignment: .top, spacing: Tokens.Space.s12) {
                    mark.frame(width: 22, height: 18, alignment: .leading).padding(.top, Tokens.Space.s1).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                        title.scaledFont(13, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                        quiet
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, Tokens.Space.s12).padding(.vertical, Tokens.Space.s10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.spoken).accessibilityHint(Copy.chatSubagentOpensHint())
            if let number = row.prNumber { PullRequestChip(number: number, dot: row.prState.dot, url: prURL).padding(.top, Tokens.Space.s12).padding(.leading, Tokens.Space.s10) }
            // the chevron is the same click, away from the chip; the row's button is the one the keyboard reaches
            Button(action: open) {
                CardChevron(open: false, width: 12).padding(.leading, Tokens.Space.s10).padding(.trailing, Tokens.Space.s12).padding(.top, Tokens.Space.s12).padding(.bottom, Tokens.Space.s10).contentShape(Rectangle())
            }
            .buttonStyle(.plain).focusable(false).accessibilityHidden(true)
        }
        .background(Color.primary.opacity(hovered ? 0.04 : 0))
        .onHover { hovered = $0 }
    }

    private var title: Text {
        guard let number = row.number else { return Text(row.title) }
        return Text("\(Text("#\(number)").foregroundStyle(.tertiary).fontWeight(.medium))  \(Text(row.title))")
    }

    private var quiet: some View {
        FlowLayout(spacing: Tokens.Space.s6) {
            ForEach(Array(row.quiet.enumerated()), id: \.offset) { index, part in
                if index > 0 { Text("·").foregroundStyle(.tertiary) }
                switch part.kind {
                case .plain: Text(part.text)
                case .step: Text(part.text).foregroundStyle(.primary).fontWeight(.medium).lineLimit(1)
                case .error: Text(part.text).foregroundStyle(.red)
                case .lane:
                    Text(part.text).scaledFont(10.5, weight: .semibold).padding(.horizontal, Tokens.Space.s8)
                        .background(Capsule().fill(Color.primary.opacity(0.1))).help(Copy.epicsSliceLaneHelp())
                }
            }
        }
        .scaledFont(12).foregroundStyle(.secondary)
    }

    @ViewBuilder private var mark: some View {
        switch row.mark {
        case .done: Disc(color: .green, mark: "✓", shape: .ready, size: 18)
        case .working: SpinningRing(diameter: 18, lineWidth: 2.5, color: .systemGreen)
        case .failed: Disc(color: .red, mark: "!", shape: .problem, size: 18)
        }
    }
}
