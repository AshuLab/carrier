import CarrierCore
import SwiftUI

/// What the agent waits for after its turn ended, as one line of the glass the agent's runs have: it opens to the tasks, and while it is shut the
/// line names one task at a time and rolls to the next every few seconds, as the line of a run rolls from step to step. Cyan, the colour of the
/// ring of a session that waits for something it started: a ring that turns, a glow that runs round the edge and a shimmer over the words (all
/// of them still with Reduce Motion), the time since the oldest began, and Stop, which stops them all (the host's `interrupt`, which with no turn
/// running stops the background tasks). It is there while the host lists a task and gone with the last. With more than one task and a host that can stop
/// one by itself, each has its own Stop in the list and the one of the line says "Stop all".
struct BackgroundWorkCard: View {
    @Environment(\.pieceTheme) private var theme
    let tasks: [CarrierCore.BackgroundTask]
    /// Stops them all.
    let stop: () -> Void
    /// Stops one of them; nil when the host cannot, and then the card has only the one Stop.
    var stopTask: ((String) -> Void)?
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long each task has the line to itself.
    private static let turn: TimeInterval = 3
    private var cyan: Color { Color.backgroundWork }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.none) {
            HStack(spacing: Tokens.Space.s6) {
                Button { toggle() } label: { header }.buttonStyle(.plain)
                    .accessibilityLabel(spoken).accessibilityHint(open ? Copy.chatBackgroundHintHide() : Copy.chatBackgroundHintShow())
                Button(stopsEach ? Copy.chatStopAll() : Copy.chatStop(), action: stop).buttonStyle(HoverTextButtonStyle(tint: theme.accent)).help(Copy.chatBackgroundStopHelp())
                    .accessibilityLabel(Copy.chatBackgroundStopLabel())
            }
            .frame(height: 30)
            if open { timeline.transition(reduceMotion ? .opacity : .reveal) }
        }
        .padding(.horizontal, Tokens.Space.s10)
        .workCard()
        .overlay { GlowEdge(color: cyan, waiting: false, moves: reduceMotion == false).allowsHitTesting(false) }
        .animation(.smooth(duration: 0.35), value: open)
        .animation(.smooth(duration: 0.3), value: tasks.map(\.id))
        .accessibilityElement(children: .contain)
    }

    /// With more than one task and a host that can, each task has its own Stop, and the one of the line says it is for all.
    private var stopsEach: Bool { stopTask != nil && tasks.count > 1 }

    private var spoken: String {
        let names = tasks.map(\.name).joined(separator: ", ")
        return Copy.chatBackgroundSpoken(count: tasks.count, names: names)
    }

    private func toggle() {
        let animation: Animation? = reduceMotion ? nil : .smooth(duration: 0.35)
        withAnimation(animation) { open.toggle() }
    }

    // MARK: the line

    private var header: some View {
        HStack(spacing: Tokens.Space.s12) {
            // the words come from a clock of their own, so the next task takes the line without anything else asking for it
            TickingTimeline(every: Self.turn) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate / Self.turn)
                let words = backgroundWords(tasks, tick: tick) ?? ""
                Color.clear.frame(maxWidth: .infinity).overlay(alignment: .leading) {
                    HStack(spacing: Tokens.Space.s10) {
                        SpinningRing(diameter: 11, lineWidth: 1.5, color: NSColor(cyan)).frame(width: 16, height: 16)
                        // the words roll up when they change: the new ones come in from below, the old ones leave above
                        ZStack(alignment: .leading) {
                            Text(words + "…").scaledFont(12.5, weight: .semibold).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                                .modifier(Shimmer(active: reduceMotion == false))
                                .id(words)
                                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                        }
                        .frame(height: 18).clipped()
                        if let count = backgroundCount(tasks) { Text(count).scaledFont(12).foregroundStyle(.tertiary).lineLimit(1).fixedSize() }
                    }
                    .padding(.leading, Tokens.Space.s4)
                }
                .clipped()
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: words)
            }
            // the right side never moves: the time since the oldest began, and the chevron as wide as a node
            HStack(spacing: Tokens.Space.s8) {
                if let oldest = tasks.compactMap(\.startedAt).min() {
                    TickingTimeline(every: 1) { context in
                        Text(workingElapsed(Int(context.date.timeIntervalSince(oldest)))).scaledFont(12).monospacedDigit().foregroundStyle(.tertiary)
                    }
                }
                LogChevron(open: open).frame(width: 16)
            }
            .fixedSize()
        }
        .scaledFont(12, weight: .medium).monospacedDigit()
        .frame(height: 30)
        .contentShape(Rectangle())
    }

    // MARK: the tasks

    private var timeline: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.none) {
            ForEach(tasks, id: \.id) { task in
                HStack(spacing: Tokens.Space.s10) {
                    // a node for each, in the column of the lead
                    Circle().fill(cyan).frame(width: 6, height: 6).frame(width: 16)
                    Text(task.name).scaledFont(11.5, design: .monospaced).lineLimit(1).truncationMode(.tail)
                    Text(task.kind.replacingOccurrences(of: "_", with: " ")).scaledFont(11).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                    Spacer(minLength: 8)
                    if let started = task.startedAt {
                        TickingTimeline(every: 1) { context in
                            Text(workingElapsed(Int(context.date.timeIntervalSince(started)))).scaledFont(11.5).monospacedDigit().foregroundStyle(.tertiary)
                        }
                    }
                    if stopsEach, let stopTask {
                        Button(Copy.chatStop()) { stopTask(task.id) }.buttonStyle(HoverTextButtonStyle(tint: nil)).help(Copy.chatStopTask(name: task.name))
                            .accessibilityLabel(Copy.chatStopTask(name: task.name))
                    }
                }
                .frame(height: 26).padding(.leading, Tokens.Space.s4).padding(.trailing, stopsEach ? Tokens.Space.s8 : Tokens.Space.s24)
                .accessibilityElement(children: .contain)
            }
        }
        .padding(.bottom, Tokens.Space.s8)
    }
}
