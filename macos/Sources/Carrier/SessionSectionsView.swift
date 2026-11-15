import AppKit
import CarrierCore
import SwiftUI

/// The Agent output tab: one centered row per session (who acted, what it did, how it ran, and a line of numbers) with its transcript
/// under it while it is open, on the window itself. The newest session is the last, like the last line of a chat. Above
/// `sessionsShown` sessions the oldest ones wait behind one row of stacked avatars, which opens them.
struct SessionSectionsView: View {
    /// The Agent output tab is a lazy stack; the smoke check reports it from this. No header stays pinned: with no background behind it, the
    /// rows would scroll under its text.
    static let layout = "lazy stack, no pinned headers"
    /// The last thing in the list: what the page scrolls to when a new session starts.
    static let endID = "end of the sessions"

    let epic: EpicRef
    let list: SessionList
    /// The epic's rounds and slices: what a review found and which slices wait. nil until the engine answers.
    var reply: EpicReply?
    @Binding var folds: SessionFolds
    @State private var flipped: Set<String> = []
    @State private var slices = SliceFolds()
    @State private var earlierOpen = false
    /// Read once when the tab appears; a profile changed in Settings shows when the epic is opened again.
    @State private var roles = RoleIdentities.none

    var body: some View {
        // the log runs top to bottom as it happened, the newest session last
        let split = earlierSessions(list.sections.map(roles.resolved))
        let shown = (earlierOpen ? split.earlier?.sections ?? [] : []) + split.recent
        // no spacing: each piece sets its own gap above itself (see `SessionMetrics`)
        LazyVStack(alignment: .leading, spacing: 0) {
            if let earlier = split.earlier { EarlierSessionsRow(earlier: earlier, open: earlierOpen) { earlierOpen.toggle() } }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, section in
                let open = folds.isOpen(section)
                Section {
                    // the flow goes down: a small arrow in the gap between one agent and the next
                    if index > 0 || split.earlier != nil { SessionFlowArrow().frame(height: SessionMetrics.between) }
                    Button { folds.toggle(section) } label: { SessionHeaderView(section: section, open: open) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(sessionRowLabel(section, open: open))
                        .accessibilityHint(open ? "Folds this session" : "Opens this session")
                    if open {
                        Color.clear.frame(height: SessionMetrics.toContent)
                        TranscriptRows(content: section.body, flipped: $flipped, slices: $slices)
                        if let card = findingsCard(reply, stage: section.stage, round: section.round) {
                            FindingsCardView(card: card).padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, 4)
                        }
                        if let result = section.result { ResultCardView(card: result, open: folds.isResultOpen(section)) { folds.toggleResult(section) } }
                        ContinueInTerminalView(section: section)
                    }
                }
            }
            Color.clear.frame(height: 1).id(Self.endID)
        }
        .environment(\.epicRepo, epic.repo)
        .task { roles = RoleIdentities(config: currentConfig()) }
    }
}

/// The arrow between two sessions, in the gap above the lower one: the agents run one after the other, top to bottom.
struct SessionFlowArrow: View {
    var body: some View {
        Image(systemName: "arrow.down").font(.scaled(10, weight: .semibold)).foregroundStyle(.quaternary)
            .frame(maxWidth: .infinity).accessibilityHidden(true)
    }
}

/// The scale of the feed (docs/macos-ui.md): every gap is one of these.
enum SessionMetrics {
    /// Between two sessions, open or folded: a session is the unit the eye scans by.
    static let between: CGFloat = 76
    /// From the row to what is under it.
    static let toContent: CGFloat = 16
}

extension View {
    /// A row inside a session's content: the whole width, its content at the left.
    func sessionRow() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if card.hasDetails {
                Button(action: toggle) { line }
                    .buttonStyle(.plain)
                    .accessibilityLabel(resultAccessibilityLabel(card, open: open))
                    .accessibilityHint(open ? "Hides the evidence" : "Shows the evidence")
            } else {
                line.accessibilityElement(children: .ignore).accessibilityLabel(resultAccessibilityLabel(card, open: open))
            }
            if let reason = card.reason {
                Text(linkedText(reason)).font(.scaled(12)).foregroundStyle(tint).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.14)))
                    .padding(.horizontal, 8).padding(.bottom, 8)
            }
            if open, let ci = card.ci {
                Text(linkedText(ci.evidence)).font(.scaled(11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
                    .padding(.horizontal, 8).padding(.bottom, 8)
            }
        }
        .workCard()
        .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, 4)
        .sessionRow()
    }

    /// The card's line, as every card of the feed has one: the tone's mark, how it ended in bold, the CI verdict, and the chevron when
    /// there is evidence to open.
    private var line: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.scaled(13)).foregroundStyle(tint).frame(width: 16, height: 16)
            Text(card.outcome).fontWeight(.semibold)
            if let ci = card.ci { Text("· \(ciVerdictText(ci.verdict))").foregroundStyle(verdictColor(ci.verdict)) }
            Spacer(minLength: 8)
            if card.hasDetails { CardChevron(open: open) }
        }
        .font(.scaled(12.5)).lineLimit(1)
        .padding(.horizontal, 10).frame(height: 30)
        .contentShape(Rectangle())
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

/// A session's row, with no card and no background: a hairline that fades out on each side of the identity, the avatar with the tool's
/// mark on its corner, the name and what it did on the first line, how it ran on the second, and the summary centered under it. Drawn
/// inside the button that folds the session, so the whole row is the click; the pointer over it brightens the hairlines and the chevron.
struct SessionHeaderView: View {
    let section: SessionSection
    let open: Bool
    @State private var hovered = false

    var body: some View {
        let text = sessionRowText(section)
        VStack(spacing: 9) {
            HStack(spacing: 18) {
                Hairline(leading: true, bright: hovered)
                HStack(spacing: 12) {
                    AgentAvatar(text: text, harness: section.agent, size: 34, working: section.state == .running)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(text.name).font(.scaled(14, weight: .bold)).lineLimit(1).layoutPriority(1)
                            Text(text.role).font(.scaled(14)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if text.how.isEmpty == false { Text(howLine(text)).lineLimit(1) }
                    }
                }
                .layoutPriority(1)
                FoldChevron(open: open, hovered: hovered)
                Hairline(leading: false, bright: hovered)
            }
            summary
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.15), value: hovered)
    }

    /// The tool's name a step brighter than the rest, which is faint.
    private func howLine(_ text: SessionRowText) -> AttributedString {
        var line = AttributedString()
        if let tool = text.tool {
            var name = AttributedString(tool)
            name.foregroundColor = Color(nsColor: .secondaryLabelColor)
            name.font = .scaled(11.5, weight: .medium)
            line += name
        }
        var rest = AttributedString((text.tool != nil && text.details.isEmpty == false ? " · " : "") + text.details.joined(separator: " · "))
        rest.foregroundColor = Color(nsColor: .tertiaryLabelColor)
        rest.font = .scaled(11.5)
        return line + rest
    }

    @ViewBuilder private var summary: some View {
        switch sessionSummary(section, open: open) {
        case .stopped(let reason):
            HStack(spacing: 8) {
                Text("stopped").font(.scaled(11, weight: .semibold)).foregroundStyle(.orange)
                    .padding(.horizontal, 10).padding(.vertical, 2).background(Capsule().fill(Color.orange.opacity(0.18)))
                // up to 300 characters from the engine: two lines, cut at the end, whole in the tooltip
                if let reason {
                    Text(reason).font(.scaled(12)).foregroundStyle(.orange).lineLimit(2).truncationMode(.tail).help(reason)
                }
            }
        case .line(let spans):
            if spans.isEmpty == false {
                Text(summaryText(spans)).font(.scaled(12)).multilineTextAlignment(.center)
            }
        }
    }

    private func summaryText(_ spans: [SummarySpan]) -> AttributedString {
        var line = AttributedString()
        for (index, span) in spans.enumerated() {
            var piece = AttributedString((index == 0 ? "" : " ") + span.text)
            switch span.style {
            case .plain: piece.foregroundColor = Color(nsColor: .secondaryLabelColor)
            case .strong: piece.foregroundColor = Color(nsColor: .labelColor); piece.font = .scaled(12, weight: .semibold)
            case .faint: piece.foregroundColor = Color(nsColor: .tertiaryLabelColor)
            case .red: piece.foregroundColor = .red
            case .green: piece.foregroundColor = .green; piece.font = .scaled(12, weight: .semibold)
            case .working: piece.foregroundColor = .green; piece.font = .scaled(12, weight: .semibold)
            }
            line += piece
        }
        return line
    }
}

/// A line of one point that fades out toward the edge of the feed, so the row reads as a pause in the log and not as a frame.
private struct Hairline: View {
    let leading: Bool
    let bright: Bool

    var body: some View {
        let line = Color.primary.opacity(bright ? 0.34 : 0.10)
        Rectangle()
            .fill(LinearGradient(colors: [.clear, line], startPoint: leading ? .leading : .trailing, endPoint: leading ? .trailing : .leading))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// The round chevron at the end of a row that folds: it turns a quarter when the row is open and brightens under the pointer.
private struct FoldChevron: View {
    let open: Bool
    let hovered: Bool

    var body: some View {
        Image(systemName: "chevron.right").font(.scaled(10, weight: .bold))
            .foregroundStyle(hovered ? Color.primary : Color.secondary)
            .rotationEffect(.degrees(open ? 90 : 0))
            .animation(.easeOut(duration: 0.2), value: open)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color.primary.opacity(hovered ? 0.18 : 0.09)))
            .accessibilityHidden(true)
    }
}

/// The row that stands for the sessions above the newest ones: their avatars overlapping, how many, which roles and how long, and a
/// chevron. Pressed it opens them under it, pressed again it closes them.
private struct EarlierSessionsRow: View {
    let earlier: EarlierSessions
    let open: Bool
    let toggle: () -> Void
    @State private var hovered = false
    /// The avatars that fit in the stack; the count says the rest.
    private static let stacked = 5

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                HStack(spacing: -8) {
                    ForEach(earlier.sections.suffix(Self.stacked)) { section in
                        AgentAvatar(text: sessionRowText(section), harness: section.agent, size: 24, working: false, mark: false)
                            .overlay(Circle().strokeBorder(Color.themeWindow, lineWidth: 2))
                    }
                }
                HStack(spacing: 4) {
                    Text(earlier.title).fontWeight(.semibold).foregroundStyle(.primary)
                    if earlier.detail.isEmpty == false { Text("· \(earlier.detail)") }
                }
                .font(.scaled(12.5)).foregroundStyle(.secondary).lineLimit(1)
                FoldChevron(open: open, hovered: hovered)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: 0.15), value: hovered)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(earlier.label)
        .accessibilityValue(open ? "Open" : "Folded")
        .accessibilityHint(open ? "Folds these sessions" : "Shows these sessions")
    }
}

/// A session's counts as pills: tool calls, edits with their lines, test runs, errors; all but the calls only above zero. With no
/// room for the words it falls back to icon and number, so the row stays one line. (The subagents' rows use it.)
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
            Image(systemName: symbol).font(.scaled(10, weight: .semibold))
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

/// Who acted, as a round picture: the profile's letter on a colour made from its name (grey, with the tool's letter, when there is no profile),
/// the tool's mark on its corner and, while it works, a green ring turning around it.
struct AgentAvatar: View {
    let text: SessionRowText
    /// The tool's name, which is also the name of its mark.
    let harness: String
    let size: CGFloat
    let working: Bool
    /// The tool's mark on the corner; the stack of earlier sessions leaves it out.
    var mark = true
    @MainActor private static var marks: [String: NSImage] = [:]

    var body: some View {
        Text(text.letter).font(.scaled(size * 0.38, weight: .bold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(disc))
            .overlay { if working { SpinningRing(diameter: size + 8, lineWidth: 2) } }
            // after the ring, so the mark is over it and not the other way round
            .overlay(alignment: .bottomTrailing) { if mark { corner.offset(x: 4, y: 4) } }
            .help(working ? "\(harness) · working" : harness)
    }

    private var disc: Color {
        if text.identified { return ProjectIcon.palette[projectColorIndex(text.name, count: ProjectIcon.palette.count)] }
        return Color(white: harness == "Claude" ? 0.37 : 0.49)
    }

    private var corner: some View {
        Group {
            if let image = Self.mark(harness) {
                Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().frame(width: 9, height: 9)
            } else {
                Text(harness.prefix(1)).font(.scaled(8, weight: .bold))
            }
        }
        .foregroundStyle(.primary)
        .frame(width: 16, height: 16)
        .background(Circle().fill(Color.themeWindow))
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1))
    }

    @MainActor static func mark(_ harness: String) -> NSImage? {
        if let known = marks[harness] { return known }
        guard let url = providerIconURL(harness), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        marks[harness] = image
        return image
    }
}
