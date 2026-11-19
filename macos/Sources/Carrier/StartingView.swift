import CarrierCore
import SwiftUI

/// The Agent output tab of an epic that is shipping but has no output yet: the steps before the first agent, in a card like the queued
/// plan's, each with what is known of it and a clock at the right (the time it began, or how long it has been going).
struct StartingView: View {
    let epic: PanelEpic
    let reply: EpicReply?

    var body: some View {
        // the clock of the workspace step runs: one tick a second is all it needs
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let steps = startingSteps(epic, reply: reply, now: Int(context.date.timeIntervalSince1970 * 1000))
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { Divider() }
                    row(step)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.08)))
        }
    }

    private func row(_ step: StartStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            mark(step.state).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title).fontWeight(.semibold).foregroundStyle(step.state == .waiting ? Color.secondary : .primary)
                if let detail = step.detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 12)
            if let clock = step.clock { Text(clock).font(.caption).monospacedDigit().foregroundStyle(.tertiary).padding(.top, 2) }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func mark(_ state: StepState) -> some View {
        switch state {
        case .done:
            Glyph(.check, size: 10, bold: true).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(Color.green)).accessibilityElement(children: .ignore).accessibilityLabel("done")
        case .current: SpinningRing(diameter: 16, lineWidth: 2.5).accessibilityLabel("in progress")
        case .waiting, .input, .error, .cancelled:
            Circle().fill(Color.secondary.opacity(0.15)).frame(width: 22, height: 22).accessibilityLabel("not started")
        }
    }
}
