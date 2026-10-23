import CarrierCore
import SwiftUI

/// The Agent output tab: one card per session with its header (avatar, who, counts, time or the stopped badge) and, below the
/// fifth, the row that opens the older ones. An open section shows its transcript under the header.
struct SessionSectionsView: View {
    /// The Agent output tab is a lazy stack whose section headers stay pinned; the smoke check reports it from these.
    static let layout = "lazy stack, pinned section headers"
    static let pinned: PinnedScrollableViews = .sectionHeaders

    let list: SessionList
    @Binding var folds: SessionFolds
    @State private var outputs = OutputFolds()

    var body: some View {
        // no spacing: the rows of a session touch, so its header, rows and foot read as one card (see `SessionCard`)
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: Self.pinned) {
            sessionSections(list.sections)
            if list.earlier.isEmpty == false {
                Button { folds.toggleEarlier() } label: { EarlierSessionsRow(count: list.earlier.count, open: folds.earlierOpen) }
                    .buttonStyle(.plain)
                    .padding(.bottom, 10)
                if folds.earlierOpen { sessionSections(list.earlier) }
            }
        }
    }

    @ViewBuilder private func sessionSections(_ sections: [SessionSection]) -> some View {
        ForEach(sections) { section in
            let open = folds.isOpen(section)
            Section {
                if open {
                    TranscriptRows(content: section.body, outputs: $outputs)
                    ForEach(section.lanes) { LaneSectionView(lane: $0, outputs: $outputs) }
                    if let result = section.result { ResultCardView(card: result) }
                    ContinueInTerminalView(section: section)
                    SessionCard.foot
                }
                Color.clear.frame(height: 10)
            } header: {
                Button { folds.toggle(section) } label: { SessionHeaderView(section: section, open: open) }
                    .buttonStyle(.plain)
                    .background { SessionCard.headerBackground(open: open) }
                    // a line between the header and what it folds, edge to edge
                    .overlay(alignment: .bottom) { if open { Divider() } }
            }
        }
    }
}

/// The row at the cut: it opens the sessions older than the five in view. The glass of the slices' rows, a clock, the title with
/// the count after it and the round chevron of every card, turned up while it is open.
struct EarlierSessionsRow: View {
    let count: Int
    let open: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock").font(.system(size: 14)).foregroundStyle(.secondary)
                .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.16)))
            HStack(spacing: 0) {
                Text("Earlier sessions").fontWeight(.semibold)
                Text(" · \(count)").foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                .rotationEffect(.degrees(open ? 90 : 0))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.secondary.opacity(0.16)))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Earlier sessions, \(count)")
        .accessibilityValue(open ? "Open" : "Closed")
        .accessibilityHint(open ? "Hides the earlier sessions" : "Shows the earlier sessions")
    }
}

/// A session is one rounded card made of pieces the lazy stack can build on its own: the header (opaque, because it stays
/// pinned over the rows scrolling under it) with its top corners, the rows between with the same tint and no corners, and the foot
/// with the bottom ones. A folded session is its header alone, rounded all round.
enum SessionCard {
    static let radius: CGFloat = 16
    static let tint = Color.secondary.opacity(0.08)

    static func headerBackground(open: Bool) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radius, bottomLeadingRadius: open ? 0 : radius, bottomTrailingRadius: open ? 0 : radius, topTrailingRadius: radius
        )
        return ZStack {
            shape.fill(Color(nsColor: .windowBackgroundColor))
            shape.fill(tint)
        }
    }

    static var foot: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius).fill(tint).frame(height: 12)
    }
}

extension View {
    /// A row inside a session's card: the card's tint behind the whole width, margins included.
    func sessionRow() -> some View {
        frame(maxWidth: .infinity, alignment: .leading).background(SessionCard.tint)
    }
}

/// The agent's closing report, under the transcript: the outcome as a pill, the summary, and for a stop the reason; what it
/// checked sits in a quiet block of its own, led by the CI verdict.
struct ResultCardView: View {
    let card: ResultCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            pill(icon, card.outcome, tint)
            MarkdownView(text: card.summary)
            if let reason = card.reason {
                Text(linkedText(reason)).font(.callout).foregroundStyle(tint).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.14)))
            }
            if let ci = card.ci {
                (Text(verdict(ci.verdict)).fontWeight(.semibold).foregroundStyle(verdictColor(ci.verdict)) + Text(" · ") + Text(linkedText(ci.evidence)))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10).sessionRow()
    }

    private func pill(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(text)
        }
        .font(.caption.weight(.semibold)).foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(color.opacity(0.18)))
    }

    private func verdict(_ word: String) -> String {
        switch word {
        case "passed": "CI passed"
        case "absent": "No CI"
        default: "CI \(word)" // a value added later still shows
        }
    }

    private func verdictColor(_ word: String) -> Color {
        switch word {
        case "passed": .green
        case "absent": .secondary
        default: .orange
        }
    }

    private var icon: String {
        switch card.tone {
        case .good: "checkmark.circle"
        case .warning: "exclamationmark.triangle"
        case .stop: "person"
        }
    }

    private var tint: Color {
        switch card.tone {
        case .good: .green
        case .warning: .orange
        case .stop: .red
        }
    }
}

struct SessionHeaderView: View {
    let section: SessionSection
    let open: Bool

    var body: some View {
        HStack(spacing: 11) {
            AgentAvatar(initial: section.initial, harness: section.agent, working: section.state == .running)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text(section.agent).fontWeight(.semibold)
                    Text(" · \(section.role) · \(section.place)").foregroundStyle(.secondary)
                }
                .lineLimit(1)
                // with no counts yet the row is still there, unseen, so the header does not grow when they arrive
                CountPills(counts: section.counts ?? SessionCounts()).opacity(section.counts != nil ? 1 : 0)
            }
            Spacer(minLength: 8)
            if section.state == .stopped {
                Text("stopped").font(.caption.weight(.medium)).foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(Color.orange.opacity(0.18)))
            } else if let time = section.timeLabel {
                Text(time).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            // a round button, as in the mockup, not a bare glyph: it says the whole header folds
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                .rotationEffect(.degrees(open ? 90 : 0))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.secondary.opacity(0.16)))
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// A session's counts as pills: tool calls, edits with their lines, test runs, errors; all but the calls only above zero. With no
/// room for the words it falls back to icon and number, so the header stays one row.
struct CountPills: View {
    let counts: SessionCounts

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(words: true)
            row(words: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(countsLine(counts))
    }

    private func row(words: Bool) -> some View {
        HStack(spacing: 5) {
            pill("terminal", counts.calls, words ? "call" : nil)
            if counts.edits > 0 { pill("pencil", counts.edits, words ? "edit" : nil, lines: true) }
            if counts.tests > 0 { pill("checkmark.circle", counts.tests, words ? "test run" : nil) }
            if counts.errors > 0 { pill("exclamationmark.triangle", counts.errors, words ? "error" : nil, tint: .red) }
        }
    }

    private func pill(_ symbol: String, _ count: Int, _ noun: String?, tint: Color? = nil, lines: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text("\(count)").fontWeight(.semibold).foregroundStyle(tint ?? .primary)
            if let noun { Text(count == 1 ? noun : noun + "s") }
            if lines {
                Text("+\(counts.added)").foregroundStyle(.green)
                Text("−\(counts.removed)").foregroundStyle(.red)
            }
        }
        .font(.caption)
        .foregroundStyle(tint ?? .secondary)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(Capsule().fill((tint ?? .secondary).opacity(tint == nil ? 0.16 : 0.18)))
    }
}

/// The provider's mark (its letter when there is none) on a grey disc; a white ring turns inside it while the agent works.
struct AgentAvatar: View {
    let initial: String
    let harness: String
    let working: Bool
    @MainActor private static var marks: [String: NSImage] = [:]

    var body: some View {
        mark.foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(harness == "Claude" ? Color(white: 0.37) : Color(white: 0.49)))
            .overlay { if working { SpinningRing(diameter: 26, lineWidth: 2, color: .white) } }
            .help(working ? "\(harness) · working" : harness)
    }

    @ViewBuilder private var mark: some View {
        if let image = Self.mark(harness) {
            Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().frame(width: 15, height: 15)
        } else {
            Text(initial).font(.system(size: 13, weight: .bold))
        }
    }

    @MainActor private static func mark(_ harness: String) -> NSImage? {
        if let known = marks[harness] { return known }
        guard let url = providerIconURL(harness), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        marks[harness] = image
        return image
    }
}
