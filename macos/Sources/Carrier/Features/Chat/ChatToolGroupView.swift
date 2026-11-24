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

    fileprivate enum Lead: Equatable { case none, spark, ring, waiting, done, stopped, failed }

    private var steps: [WorkStep] { group.steps }
    private var open: Bool { startsOpen != flipped.contains(id) && steps.isEmpty == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { toggle(id) } label: { header }
                .buttonStyle(.plain)
                .disabled(steps.isEmpty)
                .accessibilityLabel(live ? liveAccessibility : "\(group.title), \(group.summary)\(group.failed > 0 ? ", \(group.failed) failed" : "")")
                .accessibilityHint(open ? "Hides its steps" : "Shows its steps")
            if open { timeline.transition(reduceMotion ? .opacity : .reveal) }
        }
        .padding(.horizontal, 10)
        .workCard()
        .overlay { if glowing { GlowEdge(color: group.erred ? .red : waiting ? .attention : .thought, waiting: waiting, moves: reduceMotion == false).opacity(live ? 1 : 0).allowsHitTesting(false) } }
        .animation(.smooth(duration: 0.35), value: open)
        .animation(.easeOut(duration: 0.5), value: live)
        .onChange(of: live, initial: true) { was, now in finish(was: was, now: now) }
    }

    // MARK: the line

    private var header: some View {
        HStack(spacing: 12) {
            // what the run is doing: as long as it is, and what does not fit fades out at the edge of its room instead of pushing the right side
            // the room is the one offered (a clear box), and the words, as long as they are, hang in it: a fixed-size child inside a flexible frame would widen the card
            Color.clear.frame(maxWidth: .infinity).overlay(alignment: .leading) { HStack(spacing: 9) {
                if lead != .none { LeadView(lead: lead, reduceMotion: reduceMotion).transition(.scale(scale: 0.5).combined(with: .opacity)) }
                // the words roll up when they change: the new ones come in from below, the old ones leave above
                ZStack(alignment: .leading) { words.id(key).transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity))) }
                    .frame(height: 22).clipped()
                if live {
                    Text("· step \(max(1, steps.count))").font(.scaled(12)).foregroundStyle(.tertiary).lineLimit(1)
                }
                if group.failed > 0 {
                    HStack(spacing: 4) {
                        StateMark(shape: .problem, size: 12)
                        Text("\(group.failed) failed").font(.scaled(12.5))
                    }
                    .foregroundStyle(.red)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            // with no lead the words keep a little room; with one, it is in the column of the steps' nodes and the words in theirs
            .padding(.leading, lead == .none ? 4 : 0) }
            .clipped()
            .mask { HStack(spacing: 0) { Rectangle(); LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 28) } }
            // the right side never moves or shrinks: the time, and the chevron as wide as a node
            HStack(spacing: 8) {
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
        HStack(spacing: 6) {
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
            HStack(spacing: 8) {
                if let chip = group.chip(waiting: waiting) { KindChipView(chip: chip) }
                if showsLabel {
                    Text(liveLabel).font(.scaled(12.5, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                        .modifier(Shimmer(active: reduceMotion == false))
                }
            }
        } else {
            HStack(spacing: 8) {
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
        return VStack(alignment: .leading, spacing: 0) {
            if live, all.count > 4 {
                Button { toggle("\(id)/earlier") } label: {
                    Text(capped ? "\(all.count - 4) earlier steps" : "Hide earlier steps").font(.scaled(11.5)).foregroundStyle(.tertiary)
                        .padding(.leading, 25).frame(height: 22).contentShape(Rectangle())
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
        .padding(.bottom, 8)
    }

    private func toggle(_ key: String) { flip(key, in: $flipped) }
}

/// What the agent waits for after its turn ended, as one line of the glass the agent's runs have: it opens to the tasks, and while it is shut the
/// line names one task at a time and rolls to the next every few seconds, as the line of a run rolls from step to step. Cyan, the colour of the
/// ring of a session that waits for something it started: a ring that turns, a glow that runs round the edge and a shimmer over the words (all
/// of them still with Reduce Motion), the time since the oldest began, and Stop, which stops them all (the host's `interrupt`, which with no turn
/// running stops the background tasks). It is there while the host lists a task and gone with the last. With more than one task and a host that can stop
/// one by itself, each has its own Stop in the list and the one of the line says "Stop all".
struct BackgroundWorkCard: View {
    let tasks: [CarrierCore.BackgroundTask]
    /// Stops them all.
    let stop: () -> Void
    /// Stops one of them; nil when the host cannot, and then the card has only the one Stop.
    var stopTask: ((String) -> Void)?
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long each task has the line to itself.
    private static let turn: TimeInterval = 3
    private var cyan: Color { SessionRowView.backgroundWork }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button { toggle() } label: { header }.buttonStyle(.plain)
                    .accessibilityLabel(spoken).accessibilityHint(open ? "Hides the tasks" : "Shows the tasks")
                Button(stopsEach ? "Stop all" : "Stop", action: stop).buttonStyle(HoverTextButtonStyle(tint: .themeAccent)).help("Stop what the agent waits for")
                    .accessibilityLabel("Stop the background tasks")
            }
            .frame(height: 30)
            if open { timeline.transition(reduceMotion ? .opacity : .reveal) }
        }
        .padding(.horizontal, 10)
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
        return tasks.count == 1 ? "Waiting on a background task, \(names)" : "Waiting on \(tasks.count) background tasks, \(names)"
    }

    private func toggle() {
        let animation: Animation? = reduceMotion ? nil : .smooth(duration: 0.35)
        withAnimation(animation) { open.toggle() }
    }

    // MARK: the line

    private var header: some View {
        HStack(spacing: 12) {
            // the words come from a clock of their own, so the next task takes the line without anything else asking for it
            TickingTimeline(every: Self.turn) { context in
                let tick = Int(context.date.timeIntervalSinceReferenceDate / Self.turn)
                let words = backgroundWords(tasks, tick: tick) ?? ""
                Color.clear.frame(maxWidth: .infinity).overlay(alignment: .leading) {
                    HStack(spacing: 9) {
                        SpinningRing(diameter: 11, lineWidth: 1.5, color: NSColor(cyan)).frame(width: 16, height: 16)
                        // the words roll up when they change: the new ones come in from below, the old ones leave above
                        ZStack(alignment: .leading) {
                            Text(words + "…").font(.scaled(12.5, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                                .modifier(Shimmer(active: reduceMotion == false))
                                .id(words)
                                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
                        }
                        .frame(height: 18).clipped()
                        if let count = backgroundCount(tasks) { Text(count).font(.scaled(12)).foregroundStyle(.tertiary).lineLimit(1).fixedSize() }
                    }
                    .padding(.leading, 4)
                }
                .clipped()
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: words)
            }
            // the right side never moves: the time since the oldest began, and the chevron as wide as a node
            HStack(spacing: 8) {
                if let oldest = tasks.compactMap(\.startedAt).min() {
                    TickingTimeline(every: 1) { context in
                        Text(workingElapsed(Int(context.date.timeIntervalSince(oldest)))).font(.scaled(12)).monospacedDigit().foregroundStyle(.tertiary)
                    }
                }
                LogChevron(open: open).frame(width: 16)
            }
            .fixedSize()
        }
        .font(.scaled(12, weight: .medium)).monospacedDigit()
        .frame(height: 30)
        .contentShape(Rectangle())
    }

    // MARK: the tasks

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(tasks, id: \.id) { task in
                HStack(spacing: 9) {
                    // a node for each, in the column of the lead
                    Circle().fill(cyan).frame(width: 6, height: 6).frame(width: 16)
                    Text(task.name).font(.scaled(11.5, design: .monospaced)).lineLimit(1).truncationMode(.tail)
                    Text(task.kind.replacingOccurrences(of: "_", with: " ")).font(.scaled(11)).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                    Spacer(minLength: 8)
                    if let started = task.startedAt {
                        TickingTimeline(every: 1) { context in
                            Text(workingElapsed(Int(context.date.timeIntervalSince(started)))).font(.scaled(11.5)).monospacedDigit().foregroundStyle(.tertiary)
                        }
                    }
                    if stopsEach, let stopTask {
                        Button("Stop") { stopTask(task.id) }.buttonStyle(HoverTextButtonStyle(tint: nil)).help("Stop \(task.name)")
                            .accessibilityLabel("Stop \(task.name)")
                    }
                }
                .frame(height: 26).padding(.leading, 4).padding(.trailing, stopsEach ? 8 : 26)
                .accessibilityElement(children: .contain)
            }
        }
        .padding(.bottom, 8)
    }
}

/// Opens or folds a step. The change is animated here, where it is made, and not by an `.animation` on the card: the feed is a lazy stack,
/// which only moves what is under a card smoothly when the whole update is in the transaction; with the animation on the card alone the
/// card faded while everything under it jumped to its place in one frame.
private func flip(_ key: String, in flipped: Binding<Set<String>>) {
    let animation: Animation? = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .smooth(duration: 0.35)
    withAnimation(animation) {
        if flipped.wrappedValue.insert(key).inserted == false { flipped.wrappedValue.remove(key) }
    }
}

// MARK: parts

/// How the steps open: the card grows from its line and the steps stay where they are, uncovered from the top as it grows (clipped at
/// the bottom edge), instead of sliding in from above over the line.
struct RevealLayout: Layout {
    var progress: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(proposal)
        return CGSize(width: size.width, height: size.height * progress)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let content = subviews.first else { return }
        let size = content.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        content.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: size.height))
    }
}

struct Reveal: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        // the steps fade ahead of the height (squared): folding, they are gone before the card closes over them, and opening, they come in
        // once there is room for them, so a cut-off row is never seen
        RevealLayout(progress: progress) { content }.clipped().opacity(progress * progress)
    }
}

extension AnyTransition {
    static var reveal: AnyTransition { .modifier(active: Reveal(progress: 0), identity: Reveal(progress: 1)) }
}

extension Color {
    /// The violet of the agent's thinking, and of the ring that goes round a working session's icon.
    static let thought = Color(red: 0.79, green: 0.63, blue: 1.0)
}

/// The lead of the line: what the agent is doing, or how the run ended.
private struct LeadView: View {
    let lead: ChatToolGroupView.Lead
    let reduceMotion: Bool

    var body: some View {
        Group {
            switch lead {
            case .spark: Twinkle(reduceMotion: reduceMotion)
            case .ring: SpinningRing(diameter: 11, lineWidth: 1.5, color: .secondaryLabelColor)
            case .waiting: Circle().fill(Color.attention).frame(width: 8, height: 8).shadow(color: Color.attention.opacity(0.6), radius: 3)
            case .done: DoneMark()
            case .stopped: Glyph(.stopFilled, size: 8).foregroundStyle(.secondary)
            case .failed: StateMark(shape: .problem, size: 12).foregroundStyle(.red)
            case .none: EmptyView()
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// The spark of thinking: it turns a little and dims, slowly.
private struct Twinkle: View {
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            spark(0, 1)
        } else {
            MovingTimeline { context in
                let t = context.date.timeIntervalSinceReferenceDate * 2 * .pi / 2.4
                spark(sin(t) * 18, 0.75 + 0.25 * cos(t))
            }
        }
    }

    private func spark(_ degrees: Double, _ opacity: Double) -> some View {
        Glyph(.sparkles, size: 11).foregroundStyle(Color.thought).rotationEffect(.degrees(degrees)).opacity(opacity)
    }
}

/// The tick a run leaves when it ends: it bounces once.
private struct DoneMark: View {
    @State private var ticks = 0

    var body: some View {
        Glyph(.checkCircleFilled, size: 12).foregroundStyle(.green)
            .glyphKick(ticks)
            .onAppear { ticks += 1 }
    }
}

/// A light that sweeps over the text it is on, in the primary colour over the secondary one the text has.
struct Shimmer: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                MovingTimeline { context in
                    let p = (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.2)) / 2.2 * 1.6 - 0.3
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .primary, location: 0.5), .init(color: .clear, location: 1)],
                                   startPoint: UnitPoint(x: p - 0.25, y: 0.5), endPoint: UnitPoint(x: p + 0.25, y: 0.5))
                }
                .mask(content)
            }
        }
    }
}

/// The glow on the card's edge. Working, a bright arc goes round once every few seconds. Waiting for the person, it does not go anywhere: the
/// whole edge is lit and breathes, as a light that waits. Without `moves` it is still: the arc, or the edge half lit.
struct GlowEdge: View {
    let color: Color
    let waiting: Bool
    let moves: Bool
    /// The card's corners; the update pill passes half its height, a capsule.
    var cornerRadius: CGFloat = 12

    var body: some View {
        if moves {
            MovingTimeline { context in
                let now = context.date.timeIntervalSinceReferenceDate
                if waiting { breathing(0.5 + 0.5 * sin(now * 2 * .pi / 1.8)) } else { arc(now.truncatingRemainder(dividingBy: 3.4) / 3.4 * 360) }
            }
        } else if waiting {
            breathing(0.6)
        } else {
            arc(200)
        }
    }

    /// `level` from 0 to 1: how lit the edge is.
    private func breathing(_ level: Double) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(color.opacity(0.25 + 0.65 * level), lineWidth: 1.2)
            .shadow(color: color.opacity(0.35 * level), radius: 6)
    }

    private func arc(_ degrees: Double) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(
            AngularGradient(stops: [.init(color: .clear, location: 0), .init(color: .clear, location: 0.62), .init(color: color.opacity(0.95), location: 0.82),
                                    .init(color: color.opacity(0.4), location: 0.92), .init(color: .clear, location: 1)], center: .center, angle: .degrees(degrees)),
            lineWidth: 1.2
        )
    }
}

/// One thought: two lines of it, and the whole of it when the person taps.
private struct ThoughtRowView: View {
    let key: String
    let thought: Thought
    @Binding var flipped: Set<String>

    var body: some View {
        let whole = flipped.contains(key)
        HStack(alignment: .top, spacing: 9) {
            Glyph(.sparkles, size: 8).foregroundStyle(Color.thought)
                .frame(width: 16, height: 16).background(Circle().fill(Color.thought.opacity(0.2)))
            // as tall as the icon at least, so the first line is level with it
            Text(thought.text).font(.scaled(12.5)).lineSpacing(2).foregroundStyle(.secondary).lineLimit(whole ? nil : 2).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .topLeading).textSelection(.enabled)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { flip(key, in: $flipped) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thought: \(thought.text)")
    }
}

/// One call: what, on what and a short result; a failed call is red. It opens to the diff of a change or the provider's output.
private struct CallRowView: View {
    let key: String
    let call: ToolCall
    @Binding var flipped: Set<String>
    @AppStorage(Preference.chatToolOutput) private var mode
    @AppStorage(Preference.chatOpensFailedCalls) private var opensFailed

    var body: some View {
        let open = call.opensByDefault(mode, opensFailed: opensFailed) != flipped.contains(key)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                flip(key, in: $flipped)
            } label: {
                HStack(spacing: 9) {
                    node
                    Text(call.label).fontWeight(.medium)
                    Text(call.subject).codeFont(12).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if call.status != .running {
                        StateMark(shape: call.status.shape, size: 11, weight: .semibold).foregroundStyle(.red)
                        Text(call.result).foregroundStyle(call.status == .failed ? .red : .secondary)
                    }
                    LogChevron(open: open)
                }
                .font(.scaled(12))
                .foregroundStyle(call.status == .failed ? .red : .primary)
                .padding(.trailing, 6).frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(call.label) \(call.subject), \(call.result.isEmpty ? "running" : call.result)")
            .accessibilityHint(open ? "Hides the detail" : "Shows the detail")
            if open { CallDetailView(call: call).padding(.leading, 25).padding(.top, 6).padding(.bottom, 6) }
        }
    }

    /// The call's node on the rail: its kind, a ring while it goes, red when it failed.
    @ViewBuilder private var node: some View {
        ZStack {
            Circle().fill(call.status == .failed ? Color.red.opacity(0.18) : Color.primary.opacity(0.09))
            if call.status == .running {
                SpinningRing(diameter: 9, lineWidth: 1.3, color: .secondaryLabelColor)
            } else {
                Glyph(call.kind.icon, size: 8).foregroundStyle(call.status == .failed ? Color.red : .secondary)
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// What a call opens to: a change as its diff, anything else as the command (when it does not fit the row) and the output, each in the
/// code block of the messages, folded where the Output length setting says.
private struct CallDetailView: View {
    let call: ToolCall
    @State private var showAll = false
    @AppStorage(Preference.chatOutputLength) private var lines
    @AppStorage(Preference.chatDiffStyle) private var diffStyle

    var body: some View {
        if call.diff.isEmpty == false {
            DiffView(rows: call.diff, showAll: $showAll, style: diffStyle).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(alignment: .leading, spacing: 10) {
                // the row cuts a long or multi-line command in the middle: opened, the call shows all of it
                if call.kind == .shell, call.arg.contains("\n") || call.arg.count > 80 { CodeBlockView(language: "bash", code: call.arg) }
                if case .mcp = call.kind, call.arg.isEmpty == false {
                    CodeBlockView(language: resolvedCodeLanguage(nil, code: call.arg) ?? "Arguments", code: call.arg)
                }
                if call.output.isEmpty {
                    Text(call.status == .running ? "running…" : "no output").font(.scaled(11.5)).foregroundStyle(.secondary).padding(.horizontal, 6)
                } else {
                    CodeBlockView(language: "Output", code: call.output.joined(separator: "\n"), foldAfter: OutputLength(rawValue: lines)?.rawValue ?? AppPreferences.defaultOutputLength.rawValue, spare: 0)
                }
            }
        }
    }
}

/// The capsule at the start of a live line naming what the agent waits on; long names (e.g. an MCP server) are cut on one line.
struct KindChipView: View {
    let chip: KindChip
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        CappedWidth(maxWidth: 160) {
            HStack(spacing: 4) {
                if let icon = chip.icon {
                    Glyph(icon, size: 9.5)
                }
                Text(chip.label).font(.scaled(11, weight: .semibold)).lineLimit(1).truncationMode(.tail)
            }
            .foregroundStyle(foreground)
            .padding(.leading, chip.icon == nil ? 8 : 6).padding(.trailing, 8).padding(.vertical, 1)
            .background(Capsule().fill(background))
        }
        .fixedSize()
    }

    private var foreground: Color {
        let dark = scheme == .dark
        return switch chip.tint {
        case .thought: dark ? .thought : Color(red: 0.48, green: 0.29, blue: 0.75)
        case .files: dark ? Color(red: 0.42, green: 0.71, blue: 1.0) : Color(red: 0.04, green: 0.39, blue: 0.78)
        case .shell: dark ? Color(red: 0.31, green: 0.85, blue: 0.45) : Color(red: 0.11, green: 0.54, blue: 0.24)
        case .mcp: dark ? Color(red: 1.0, green: 0.70, blue: 0.25) : Color(red: 0.66, green: 0.39, blue: 0.0)
        case .subagents: dark ? Color(red: 0.84, green: 0.55, blue: 1.0) : Color(red: 0.54, green: 0.18, blue: 0.75)
        case .attention: .attention
        }
    }

    private var background: Color {
        switch chip.tint {
        case .thought: Color.thought.opacity(0.16)
        case .files: Color.blue.opacity(0.16)
        case .shell: Color.green.opacity(0.14)
        case .mcp: Color.orange.opacity(0.16)
        case .subagents: Color.purple.opacity(0.18)
        case .attention: Color.attention.opacity(0.20)
        }
    }
}

/// Proposes at most `maxWidth` even when the parent proposes an unspecified width, so a chip truncates instead of widening the line.
private struct CappedWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let cap = proposal.width.map { min($0, maxWidth) } ?? maxWidth
        return child.sizeThatFits(ProposedViewSize(width: cap, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

extension Color {
    /// The timer of a slow call: the system's amber on dark, a deeper one on light, where the system's is too pale to read.
    static let slowCall = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemOrange : NSColor(red: 0.70, green: 0.36, blue: 0, alpha: 1)
    })
}
