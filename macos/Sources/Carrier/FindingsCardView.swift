import CarrierCore
import SwiftUI

// The findings of a review round as one work card (docs/macos-ui.md, "The review findings card"; F1 of
// docs/research/macos-app-design/explorations/carrier-view-cards.html): the verdict on top, a row per finding, blockers first.

/// The review's verdict as the header, then a row per finding: a dot for its kind, its id, what it says, its mark and a link to the
/// discussion. It shows in the reviewer's session and, with the marks the next round verified, in the fixer's.
struct FindingsCardView: View {
    let card: FindingsCard
    /// Folded by the person; kept here, so a card the lazy feed recycles opens again.
    @State private var folded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { flipCard { folded.toggle() } } label: { header }
                .buttonStyle(.plain)
                .disabled(card.rows.isEmpty)
                .accessibilityLabel("\(card.title), \(card.summary)\(card.prNumber.map { ", pull request \($0)" } ?? "")")
                .accessibilityHint(card.rows.isEmpty ? "" : folded ? "Shows the findings" : "Hides the findings")
            if folded == false, card.rows.isEmpty == false {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(card.rows.enumerated()), id: \.offset) { _, row in
                        SettingsDivider()
                        FindingRowView(row: row)
                    }
                }
            }
        }
        .workCard()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Group {
                switch card.verdict {
                case .ready: Disc(color: .green, mark: "✓", shape: .ready, size: 16)
                case .changesRequested: Disc(color: .orange, mark: "!", shape: .needsAttention, size: 16)
                }
            }
            .frame(width: 16, height: 16).accessibilityHidden(true)
            Text(card.title).fontWeight(.semibold)
            Text(card.summary).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            if let number = card.prNumber { PullRequestChip(number: number, dot: nil, url: card.prURL) }
            CardChevron(open: folded == false).opacity(card.rows.isEmpty ? 0 : 1)
        }
        .font(.scaled(12.5))
        .padding(.horizontal, 10).frame(height: 30)
        .contentShape(Rectangle())
    }
}

private struct FindingRowView: View {
    let row: FindingRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(dot).frame(width: 8, height: 8).padding(.top, 5).frame(width: 14, alignment: .leading).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if let id = row.id { Text(id).font(.scaled(12, weight: .semibold, design: .monospaced)).textSelection(.enabled) }
                Text(row.text).font(.scaled(12.5)).foregroundStyle(.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            .opacity(row.isFixed ? 0.55 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 7) {
                if let mark = row.mark { markChip(mark) }
                if let link = row.url.flatMap(browserURL) {
                    Link(destination: link) { Image(systemName: "arrow.up.right").font(.scaled(10, weight: .semibold)).foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).help(link.absoluteString).accessibilityLabel("Open the discussion")
                }
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel([row.kind == .blocker ? "Blocker" : "Suggestion", row.id, row.text, row.mark?.text].compactMap { $0 }.joined(separator: ", "))
    }

    /// Orange for a blocker, grey for a suggestion, green once verified fixed.
    private var dot: Color {
        if row.isFixed { return .green }
        return row.kind == .blocker ? .orange : Color.secondary.opacity(0.6)
    }

    private func markChip(_ mark: FindingMark) -> some View {
        let tint: Color = switch mark {
        case .new: .orange
        case .carried: .red
        case .fixed: .green
        }
        // an approximate mark was found by matching titles; the words say so
        return Text(mark.text + (row.approximate ? " ≈" : "")).font(.scaled(10.5, weight: .semibold)).foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.16)))
            .help(row.approximate ? "The reviewer gave no ids, so this mark comes from matching titles" : "")
    }
}
