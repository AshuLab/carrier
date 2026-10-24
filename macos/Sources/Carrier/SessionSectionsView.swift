import CarrierCore
import SwiftUI

/// The Agent output tab: one card per session with its header (avatar, who, counts, time or the stopped badge) and, below the
/// fifth, the row (above the first one) that opens the older ones. The newest session is the last, like the last line of a chat. An open section shows its transcript under the header.
struct SessionSectionsView: View {
    /// The Agent output tab is a lazy stack whose section headers stay pinned; the smoke check reports it from these.
    static let layout = "lazy stack, pinned section headers"
    static let pinned: PinnedScrollableViews = .sectionHeaders
    /// The last thing in the list: what the page scrolls to when a new session starts.
    static let endID = "end of the sessions"

    let epic: EpicRef
    let list: SessionList
    @Binding var folds: SessionFolds
    @State private var outputs = OutputFolds()
    @State private var groups = GroupFolds()
    @State private var slices = SliceFolds()

    var body: some View {
        // no spacing: the rows of a session touch, so its header, rows and foot read as one card (see `SessionCard`)
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: Self.pinned) {
            // the log runs top to bottom as it happened, the newest session last
            sessionSections(list.sections)
            Color.clear.frame(height: 1).id(Self.endID)
        }
    }

    @ViewBuilder private func sessionSections(_ sections: [SessionSection]) -> some View {
        ForEach(sections) { section in
            let open = folds.isOpen(section)
            Section {
                if open {
                    TranscriptRows(content: section.body, outputs: $outputs, groups: $groups, slices: $slices)
                    if let result = section.result { ResultCardView(card: result, open: folds.isResultOpen(section)) { folds.toggleResult(section) } }
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

/// The agent's closing report, the foot of the session under a hairline: one row like those of the log (a glyph, how it ended, the
/// CI verdict) that opens on the evidence in the flat block of a command's output. A stop's reason is drawn under the row, never
/// behind a click. The summary is not drawn: it is the engine's hand-off to the next agent, and the agent's last message above
/// already tells the person.
struct ResultCardView: View {
    let card: ResultCard
    let open: Bool
    let toggle: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            if card.hasDetails {
                Button(action: toggle) { row }
                    .buttonStyle(.plain)
                    .accessibilityLabel(resultAccessibilityLabel(card, open: open))
                    .accessibilityHint(open ? "Hides the evidence" : "Shows the evidence")
            } else {
                row.accessibilityElement(children: .ignore).accessibilityLabel(resultAccessibilityLabel(card, open: open))
            }
            if let reason = card.reason {
                Text(linkedText(reason)).font(.callout).foregroundStyle(tint).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.14)))
                    .padding(.horizontal, LogMetrics.iconColumn).padding(.bottom, 10)
            }
            if open, let ci = card.ci {
                Text(linkedText(ci.evidence)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
                    .padding(.horizontal, LogMetrics.iconColumn).padding(.bottom, 10)
            }
        }
        .sessionRow()
    }

    private var row: some View {
        HStack(spacing: LogMetrics.gap) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
                .frame(width: LogMetrics.iconWidth, height: LogMetrics.iconWidth)
            HStack(spacing: 4) {
                Text(card.outcome).fontWeight(.semibold)
                if let ci = card.ci { Text("· \(verdict(ci.verdict))").foregroundStyle(verdictColor(ci.verdict)) }
            }
            .font(.system(size: 12)).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            // the columns of a call, so the chevron stands where the log's chevrons stand
            CallColumns(duration: nil, status: .ok, chevron: (card.hasDetails, open))
        }
        .padding(.horizontal, LogMetrics.iconColumn)
        .frame(height: LogMetrics.groupLine)
        .background(Color.primary.opacity(hovered && card.hasDetails ? 0.05 : 0))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
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
        case "passed", "absent": .secondary
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
