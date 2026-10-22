import CarrierCore
import SwiftUI

/// The Agent output tab: one card per session with its header (avatar, who, counts, time or the stopped badge) and, below the
/// last, how many earlier sessions there are. An open section shows its transcript under the header.
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
            ForEach(list.sections) { section in
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
            if let earlier = list.earlier { Text(earlier).font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 6) }
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

/// The agent's closing report, under the transcript: the outcome, its summary, the CI line and, for a stop, the reason.
struct ResultCardView: View {
    let card: ResultCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.outcome).font(.caption.weight(.semibold)).foregroundStyle(tint)
                .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(tint.opacity(0.18)))
            Text(linkedText(card.summary)).textSelection(.enabled)
            if let ci = card.ci { Text(linkedText(ci)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            if let reason = card.reason {
                Text(linkedText(reason)).font(.callout).foregroundStyle(tint).textSelection(.enabled)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8).sessionRow()
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
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text(section.agent).fontWeight(.semibold)
                    Text(" · \(section.role) · \(section.place)").foregroundStyle(.secondary)
                }
                .lineLimit(1)
                if section.counts != nil { Text(Self.counts(section.countRuns)).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
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

    /// The counts line with the lines added in green and the removed and the errors in red.
    static func counts(_ runs: [CountRun]) -> AttributedString {
        runs.reduce(into: AttributedString()) { line, run in
            var piece = AttributedString(run.text)
            switch run.tone {
            case .plain: break
            case .added: piece.foregroundColor = .green
            case .removed, .error: piece.foregroundColor = .red
            }
            line += piece
        }
    }
}

/// The agent's letter on a grey disc; a white ring turns inside it while the agent works.
struct AgentAvatar: View {
    let initial: String
    let harness: String
    let working: Bool

    var body: some View {
        Text(initial).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(harness == "Claude" ? Color(white: 0.37) : Color(white: 0.49)))
            .overlay { if working { SpinningRing(diameter: 26, lineWidth: 2, color: .white) } }
            .help(working ? "\(harness) · working" : harness)
    }
}
