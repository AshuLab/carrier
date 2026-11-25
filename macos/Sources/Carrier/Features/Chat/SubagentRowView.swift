import CarrierCore
import SwiftUI

/// A subagent as a row of the conversation, under the run that launched it (docs/research/macos-app-design/explorations/subagent-view.html): its
/// state, its type as a chip, its title, the step it is on, its steps and its timer, on one line as high as a "Worked" card's. What does not fit
/// is cut, never wrapped, so the row is one height at any width. Where a conversation or a subagent view draws it, tapping it opens that
/// subagent's view (`openSubagent`) and it ends in a chevron.
struct SubagentRowView: View {
    let subagent: Subagent
    /// The time the timer reads instead of the clock; a test sets it.
    var clock: Date?
    @Environment(\.openSubagent) private var open
    @State private var hovered = false

    var body: some View {
        let row = line
        if let open {
            Button { open(subagent.id) } label: { row }
                .buttonStyle(.plain).onHover { hovered = $0 }
                .overlay { if hovered { RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(Color.primary.opacity(0.04)).allowsHitTesting(false) } }
                .accessibilityHint("Opens the subagent")
        } else {
            row
        }
    }

    /// "1 step", "3 steps": the row's words and the label that reads it aloud.
    private var steps: String { "\(subagent.steps) \(subagent.steps == 1 ? "step" : "steps")" }

    private var line: some View {
        HStack(spacing: Tokens.Space.s10) {
            lead.frame(width: 16, height: 16)
            KindChipView(chip: .subagent(type: subagent.type))
            Text(subagent.name).scaledFont(12.5, weight: .semibold).foregroundStyle(.primary).lineLimit(1).truncationMode(.tail)
                .layoutPriority(1)
            Text(subagent.words).scaledFont(12).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(steps).scaledFont(12).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
            timer
            if open != nil { CardChevron(open: false, width: 9) }
        }
        .scaledFont(12, weight: .medium).monospacedDigit()
        .padding(.horizontal, Tokens.Space.s10)
        .frame(height: 30)
        .workCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(subagent.type) subagent, \(subagent.name), \(subagent.words), \(steps)")
        .contentShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
    }

    @ViewBuilder private var lead: some View {
        switch subagent.status {
        case .running: SpinningRing(diameter: 11, lineWidth: 1.5, color: .secondaryLabelColor)
        case .completed: Glyph(.checkCircleFilled, size: 12).foregroundStyle(.green)
        case .failed: StateMark(shape: .problem, size: 12).foregroundStyle(.red)
        case .stopped: Glyph(.stopFilled, size: 8).foregroundStyle(.secondary)
        }
    }

    /// Ticking while it runs, its own duration once it ended.
    @ViewBuilder private var timer: some View {
        if subagent.status == .running {
            TickingTimeline(every: 1) { context in
                time(Int((clock ?? context.date).timeIntervalSince1970 * 1000))
            }
        } else {
            time(0)
        }
    }

    private func time(_ now: Int) -> some View {
        Text(formatCallDuration(subagent.elapsedMs(now: now))).scaledFont(12).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
    }
}

private struct OpenSubagentKey: EnvironmentKey { static let defaultValue: ((String) -> Void)? = nil }

extension EnvironmentValues {
    /// What tapping a subagent's row does, given the call that launched it; nil where a row is only shown.
    var openSubagent: ((String) -> Void)? {
        get { self[OpenSubagentKey.self] }
        set { self[OpenSubagentKey.self] = newValue }
    }
}
