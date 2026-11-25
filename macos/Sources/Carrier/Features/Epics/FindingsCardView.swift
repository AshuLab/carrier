import CarrierCore
import SwiftUI

// The findings of a review round as one work card (docs/ui.md, "The review findings card"; the mockup is "Proposed" of
// docs/research/macos-app-design/explorations/carrier-view-review.html): the verdict on top, a row per finding, blockers first, and the
// reviewer's verification as the foot.

/// The review's verdict as the header, then a row per finding: its kind in a word, its id, what it says, its mark, the whole row a link to
/// the discussion. Under an approval the findings are suggestions, and wait folded. It shows in the reviewer's session, with the
/// verification as its foot, and, with the marks the next round verified, in the fixer's.
struct FindingsCardView: View {
    let card: FindingsCard
    /// Who wrote the review, for the header; nil in the fixer's session, where the findings are not its own.
    let reviewer: String?
    /// What the reviewer says it checked, the foot of the card; nil when it has none (or the card is the fixer's).
    let verification: ResultCard.CI?
    let evidenceOpen: Bool
    let toggleEvidence: () -> Void
    /// Opened by the person; kept here, so a card the lazy feed recycles folds again.
    @State private var suggestionsOpen = false

    /// An approved review's rows are suggestions: they wait behind one line.
    private var foldsRows: Bool { card.verdict == .ready && card.rows.isEmpty == false }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.none) {
            header
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(card.title), \(card.summary), \(roundText)\(card.prNumber.map { ", pull request \($0)" } ?? "")")
            if foldsRows {
                SettingsDivider()
                Button { flipCard { suggestionsOpen.toggle() } } label: { foldLine }
                    .buttonStyle(.plain)
                    .accessibilityLabel(card.summary)
                    .accessibilityHint(suggestionsOpen ? "Hides the findings" : "Shows the findings")
            }
            if foldsRows == false || suggestionsOpen {
                ForEach(Array(card.rows.enumerated()), id: \.offset) { _, row in
                    SettingsDivider()
                    FindingRowView(row: row)
                }
            }
            if let verification {
                SettingsDivider()
                Button(action: toggleEvidence) { foot(verification) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Verified, \(ciVerdictText(verification.verdict))")
                    .accessibilityHint(evidenceOpen ? "Hides the evidence" : "Shows the evidence")
                if evidenceOpen { EvidenceBlock(text: verification.evidence).padding(.top, Tokens.Space.s8) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .workCard()
    }

    private var roundText: String { "Round \(card.round)" + (reviewer.map { " · \($0)" } ?? "") }

    private var header: some View {
        HStack(spacing: Tokens.Space.s8) {
            Group {
                switch card.verdict {
                case .ready: Disc(color: .green, mark: "✓", shape: .ready, size: 16)
                case .changesRequested: Disc(color: .orange, mark: "!", shape: .needsAttention, size: 16)
                }
            }
            .frame(width: 16, height: 16).accessibilityHidden(true)
            Text(card.title).fontWeight(.semibold).lineLimit(1).layoutPriority(1)
            Text(card.summary).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Text(roundText).font(.scaled(12)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
            if let number = card.prNumber { PullRequestChip(number: number, dot: nil, url: card.prURL).layoutPriority(1) }
        }
        .font(.scaled(12.5))
        .padding(.horizontal, Tokens.Space.s10).frame(height: 30)
    }

    /// The one line an approval's suggestions wait behind.
    private var foldLine: some View {
        HStack(spacing: Tokens.Space.s8) {
            Text(plural(card.rows.count, "suggestion")).font(.scaled(12.5)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            CardChevron(open: suggestionsOpen, width: 12)
        }
        .padding(.horizontal, Tokens.Space.s12).frame(height: 32).frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .hoverFill()
    }

    private func foot(_ ci: ResultCard.CI) -> some View {
        HStack(spacing: Tokens.Space.s8) {
            Text("Verified · \(ciVerdictText(ci.verdict))").font(.scaled(12)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            CardChevron(open: evidenceOpen)
        }
        .padding(.horizontal, Tokens.Space.s10).frame(height: 30).frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}

/// A finding: its kind as a word, its id, what it says and, at the right, its mark and the arrow that shows under the pointer. With a link
/// the whole row opens the discussion and lights up under the pointer.
private struct FindingRowView: View {
    let row: FindingRow

    var body: some View {
        if let link = row.url.flatMap(browserURL) {
            Link(destination: link) { content(linked: true) }
                .buttonStyle(.plain).help(link.absoluteString)
                .accessibilityHint("Opens the discussion")
        } else {
            content(linked: false)
        }
    }

    private func content(linked: Bool) -> some View {
        HStack(alignment: .top, spacing: Tokens.Space.s10) {
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                HStack(spacing: Tokens.Space.s8) {
                    Text(row.kind == .blocker ? "BLOCKER" : "SUGGESTION").font(.scaled(10.5, weight: .bold)).foregroundStyle(kindTint)
                    if let id = row.id { Text(id).font(.scaled(12, weight: .semibold, design: .monospaced)).lineLimit(1).truncationMode(.middle) }
                }
                Text(row.text).font(.scaled(12.5)).foregroundStyle(.secondary).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
            }
            .opacity(row.isFixed ? 0.55 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Tokens.Space.s8) {
                if let mark = row.mark { markChip(mark) }
                if linked { HoverArrow() }
            }
            .padding(.top, Tokens.Space.s1)
        }
        .padding(.horizontal, Tokens.Space.s12).padding(.vertical, Tokens.Space.s10).frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(HoverFillIf(enabled: linked))
        .accessibilityElement(children: .combine)
        .accessibilityLabel([row.kind == .blocker ? "Blocker" : "Suggestion", row.id, row.text, row.mark.map { $0.text + (row.approximate ? " approximately" : "") }].compactMap { $0 }.joined(separator: ", "))
    }

    /// Orange for a blocker, grey for a suggestion, green once verified fixed.
    private var kindTint: Color {
        if row.isFixed { return .green }
        return row.kind == .blocker ? .orange : Color.secondary.opacity(0.8)
    }

    private func markChip(_ mark: FindingMark) -> some View {
        let tint: Color = switch mark {
        case .new: .orange
        case .carried: .red
        case .fixed: .green
        }
        // an approximate mark was found by matching titles; the words say so
        return Text(mark.text + (row.approximate ? " ≈" : "")).font(.scaled(10.5, weight: .semibold)).foregroundStyle(tint)
            .padding(.horizontal, Tokens.Space.s8).padding(.vertical, Tokens.Space.s1)
            .background(Capsule().fill(tint.opacity(0.16)))
            .help(row.approximate ? "The reviewer gave no ids, so this mark comes from matching titles" : "")
    }
}

/// The arrow at the end of a link row: there, but only seen while the pointer is over the row.
private struct HoverArrow: View {
    @Environment(\.rowHovered) private var hovered

    var body: some View {
        Glyph(.arrowUpRight, size: 10).foregroundStyle(.tertiary).opacity(hovered ? 1 : 0).accessibilityHidden(true)
    }
}

private struct RowHoveredKey: EnvironmentKey { static let defaultValue = false }

private extension EnvironmentValues {
    var rowHovered: Bool {
        get { self[RowHoveredKey.self] }
        set { self[RowHoveredKey.self] = newValue }
    }
}

/// A 4 % fill under the pointer, as the rows of the other work cards take, and the row's hover for what is inside it.
private struct HoverFillIf: ViewModifier {
    let enabled: Bool
    @State private var hovered = false

    func body(content: Content) -> some View {
        content
            .environment(\.rowHovered, hovered)
            .background(Color.primary.opacity(enabled && hovered ? 0.04 : 0))
            .onHover { hovered = $0 }
    }
}

private extension View {
    func hoverFill() -> some View { modifier(HoverFillIf(enabled: true)) }
}
