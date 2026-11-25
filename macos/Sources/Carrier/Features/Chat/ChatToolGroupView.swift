import CarrierCore
import SwiftUI

/// What the agent did in one run, as one glass card (docs/research/macos-app-design/explorations/reasoning-card-states.html): a single line
/// that is always folded until the person opens it, and opens to the steps in the order they were taken, a violet node for each thought and
/// a node for each call, with no line between them. While the agent works the line says what it is doing (thinking, the command that runs, waiting for an
/// answer), with its step, what failed and a timer, and three effects tell it is alive: a shimmer over the words, a glow that runs round
/// the edge (amber while it waits for the person) and a roll when the words change. When the work ends the glow fades, the words roll to
/// the summary and a tick bounces once and gives its place back. With Reduce Motion the effects stop; the icon and the words still tell it.
/// Open or folded is kept in `flipped` by id so a row the lazy feed recycles keeps its state. A session's conversation and the epic's Agent
/// output both draw their runs with it.
struct ChatToolGroupView: View {
    let id: String
    let group: ToolGroup
    /// Whether the agent is working in this run now (`workInProgress`).
    var live = false
    /// Whether an approval waits for the person.
    var waiting = false
    /// When the turn began, in milliseconds: the timer of a live run counts from it, as the person waited from then.
    var since: Int?
    /// Whether the card is open until the person flips it (the Tool output setting set to expanded); a session's runs start folded.
    var startsOpen = false
    /// The time the timers read instead of the clock; a test sets it.
    var clock: Date?
    @Binding var flipped: Set<String>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the lead slot shows once the run is not live: a tick for a moment after it ended, a square when it was stopped, nothing.
    @State private var finished = Lead.none
    @State private var glowing = false

    enum Lead: Equatable { case none, spark, ring, waiting, done, stopped, failed }

    private var steps: [WorkStep] { group.steps }
    private var open: Bool { startsOpen != flipped.contains(id) && steps.isEmpty == false }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.none) {
            Button { toggle(id) } label: { header }
                .buttonStyle(.plain)
                .disabled(steps.isEmpty)
                .accessibilityLabel(live ? liveAccessibility : "\(group.title), \(group.summary)\(group.failed > 0 ? ", \(group.failed) failed" : "")")
                .accessibilityHint(open ? "Hides its steps" : "Shows its steps")
            if open { timeline.transition(reduceMotion ? .opacity : .reveal) }
        }
        .padding(.horizontal, Tokens.Space.snug)
        .workCard()
        .overlay { if glowing { GlowEdge(color: group.erred ? .red : waiting ? .attention : .thought, waiting: waiting, moves: reduceMotion == false).opacity(live ? 1 : 0).allowsHitTesting(false) } }
        .animation(.smooth(duration: 0.35), value: open)
        .animation(.easeOut(duration: 0.5), value: live)
        .onChange(of: live, initial: true) { was, now in finish(was: was, now: now) }
    }

    // MARK: the line

    private var header: some View {
        HStack(spacing: Tokens.Space.md) {
            // what the run is doing: as long as it is, and what does not fit fades out at the edge of its room instead of pushing the right side
            // the room is the one offered (a clear box), and the words, as long as they are, hang in it: a fixed-size child inside a flexible frame would widen the card
            Color.clear.frame(maxWidth: .infinity).overlay(alignment: .leading) { HStack(spacing: Tokens.Space.snug) {
                if lead != .none { LeadView(lead: lead, reduceMotion: reduceMotion).transition(.scale(scale: 0.5).combined(with: .opacity)) }
                // the words roll up when they change: the new ones come in from below, the old ones leave above
                ZStack(alignment: .leading) { words.id(key).transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity))) }
                    .frame(height: 22).clipped()
                if live {
                    Text("· step \(max(1, steps.count))").font(.scaled(12)).foregroundStyle(.tertiary).lineLimit(1)
                }
                if group.failed > 0 {
                    HStack(spacing: Tokens.Space.xs) {
                        StateMark(shape: .problem, size: 12)
                        Text("\(group.failed) failed").font(.scaled(12.5))
                    }
                    .foregroundStyle(.red)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            // with no lead the words keep a little room; with one, it is in the column of the steps' nodes and the words in theirs
            .padding(.leading, lead == .none ? Tokens.Space.xs : Tokens.Space.none) }
            .clipped()
            .mask { HStack(spacing: Tokens.Space.none) { Rectangle(); LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 28) } }
            // the right side never moves or shrinks: the time, and the chevron as wide as a node
            HStack(spacing: Tokens.Space.sm) {
                if live {
                    TickingTimeline(every: 1) { context in
                        liveTimers(group.liveTimer(now: Int((clock ?? context.date).timeIntervalSince1970 * 1000), turnStart: since))
                    }
                } else {
                    if group.added > 0 { Text("+\(group.added)").foregroundStyle(.green) }
                    if group.removed > 0 { Text("−\(group.removed)").foregroundStyle(.red) }
                    if let ms = group.durationMs { Text(formatCallDuration(ms)).foregroundStyle(.tertiary) }
                }
                LogChevron(open: open).opacity(steps.isEmpty ? 0 : 1).frame(width: 16)
            }
            .fixedSize()
        }
        .font(.scaled(12, weight: .medium)).monospacedDigit()
        .frame(height: 30)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: key)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: lead)
    }

    /// The running call's own time, amber once the call is slow (a Shell or MCP call past 30 seconds), and the turn's beside it, quieter, while it is longer.
    /// Neither wraps: the right side keeps its width and never moves the words.
    private func liveTimers(_ timer: LiveTimer) -> some View {
        HStack(spacing: Tokens.Space.tight) {
            if let turn = timer.turnMs {
                Text(formatCallDuration(turn)).font(.scaled(11.5)).foregroundStyle(.quaternary).lineLimit(1)
            }
            Text(formatCallDuration(timer.primaryMs)).font(.scaled(12)).foregroundStyle(timer.slow ? AnyShapeStyle(Color.slowCall) : AnyShapeStyle(.tertiary)).lineLimit(1)
        }
        .monospacedDigit()
        .fixedSize()
    }

    /// What the line says now; it is also what rolls when it changes.
    private var key: String {
        if live { return "\(group.chip(waiting: waiting)?.label ?? "")|\(liveLabel)" }
        return "\(group.title) \(group.summary)"
    }

    /// The words after the chip: none while the chip already says Thinking, which they would only repeat.
    private var showsLabel: Bool { group.chip(waiting: waiting) != .thinking }

    private var liveAccessibility: String {
        if let chip = group.chip(waiting: waiting) { return showsLabel ? "Working, \(chip.label), \(liveLabel)" : "Working, \(chip.label)" }
        return "Working, \(liveLabel)"
    }

    private var liveLabel: String {
        if waiting { return "Waiting for your answer" }
        return group.doing.map { "\($0)…" } ?? "Thinking…"
    }

    @ViewBuilder private var words: some View {
        if live {
            HStack(spacing: Tokens.Space.sm) {
                if let chip = group.chip(waiting: waiting) { KindChipView(chip: chip) }
                if showsLabel {
                    Text(liveLabel).font(.scaled(12.5, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                        .modifier(Shimmer(active: reduceMotion == false))
                }
            }
        } else {
            HStack(spacing: Tokens.Space.sm) {
                Text(group.title).font(.scaled(12.5, weight: .semibold)).foregroundStyle(group.erred ? Color.red : .primary)
                Text(group.summary).font(.scaled(12.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var lead: Lead {
        guard live else { return finished }
        if waiting { return .waiting }
        return group.doing == nil ? .spark : .ring
    }

    /// The edge glow is drawn while live and for the half second it takes to fade; the tick shows when a run ends by itself and gives its
    /// place back after a moment. A run that was never live (history) shows nothing of this.
    private func finish(was: Bool, now: Bool) {
        if now {
            glowing = true
            return
        }
        finished = group.erred ? .failed : group.isStopped ? .stopped : (was ? .done : .none)
        guard was else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(550))
            glowing = false
            guard finished == .done else { return }
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.smooth(duration: 0.3)) { finished = .none }
        }
    }

    // MARK: the steps

    private var timeline: some View {
        let all = steps
        // live, only the last four are drawn so the card does not push the feed while the agent works; the rest is one tap away
        let capped = live && all.count > 4 && flipped.contains("\(id)/earlier") == false
        let shown = capped ? Array(all.suffix(4)) : all
        return VStack(alignment: .leading, spacing: Tokens.Space.none) {
            if live, all.count > 4 {
                Button { toggle("\(id)/earlier") } label: {
                    Text(capped ? "\(all.count - 4) earlier steps" : "Hide earlier steps").font(.scaled(11.5)).foregroundStyle(.tertiary)
                        .padding(.leading, Tokens.Space.xxl).frame(height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ForEach(shown) { step in
                switch step {
                case .thought(let thought): ThoughtRowView(key: "\(id)/\(thought.id)", thought: thought, flipped: $flipped)
                case .call(let call): CallRowView(key: "\(id)/\(call.id)", call: call, flipped: $flipped)
                }
            }
        }
        .padding(.bottom, Tokens.Space.sm)
    }

    private func toggle(_ key: String) { flip(key, in: $flipped) }
}
