import CarrierCore
import SwiftUI

/// What the agent did in one run, as one glass card (docs/research/macos-app-design/explorations/reasoning-card-states.html): a single line
/// that is always folded until the person opens it, and opens to the steps in the order they were taken, a violet node for each thought and
/// a node for each call, with no line between them. While the agent works the line says what it is doing (thinking, the command that runs, waiting for an
/// answer), with its step, what failed and a timer, and three effects tell it is alive: a shimmer over the words, a glow that runs round
/// the edge (amber while it waits for the person) and a roll when the words change. When the work ends the glow fades, the words roll to
/// the summary and a tick bounces once and gives its place back. With Reduce Motion the effects stop; the icon and the words still tell it.
/// Open or folded is kept in `flipped` by id so a row the lazy feed recycles keeps its state.
struct ChatToolGroupView: View {
    let id: String
    let group: ToolGroup
    /// Whether the agent is working in this run now (`workInProgress`).
    var live = false
    /// Whether an approval waits for the person.
    var waiting = false
    /// When the turn began, in milliseconds: the timer of a live run counts from it, as the person waited from then.
    var since: Int?
    @Binding var flipped: Set<String>
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the lead slot shows once the run is not live: a tick for a moment after it ended, a square when it was stopped, nothing.
    @State private var finished = Lead.none
    @State private var glowing = false

    fileprivate enum Lead: Equatable { case none, spark, ring, waiting, done, stopped, failed }

    private var steps: [WorkStep] { group.steps }
    private var open: Bool { flipped.contains(id) && steps.isEmpty == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { toggle(id) } label: { header }
                .buttonStyle(.plain)
                .disabled(steps.isEmpty)
                .accessibilityLabel(live ? "Working, \(liveLabel)" : "\(group.title), \(group.summary)\(group.failed > 0 ? ", \(group.failed) failed" : "")")
                .accessibilityHint(open ? "Hides its steps" : "Shows its steps")
            if open { timeline.transition(reduceMotion ? .opacity : .reveal) }
        }
        .padding(.horizontal, 10)
        // the glass, tint and fill of the code blocks, so the card and what it opens to are one family
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
        .glassEffect(.regular.tint(scheme == .dark ? Color.black.opacity(0.3) : nil), in: .rect(cornerRadius: 12))
        .overlay { if glowing { GlowEdge(color: group.erred ? .red : waiting ? .attention : .thought, waiting: waiting, moves: reduceMotion == false).opacity(live ? 1 : 0).allowsHitTesting(false) } }
        .animation(.smooth(duration: 0.28), value: open)
        .animation(.easeOut(duration: 0.5), value: live)
        .onChange(of: live, initial: true) { was, now in finish(was: was, now: now) }
    }

    // MARK: the line

    private var header: some View {
        HStack(spacing: 8) {
            // as wide as a node, so the chevron sits right over the nodes
            LogChevron(open: open).opacity(steps.isEmpty ? 0 : 1).frame(width: 16)
            if lead != .none { LeadView(lead: lead, reduceMotion: reduceMotion).transition(.scale(scale: 0.5).combined(with: .opacity)) }
            // the words roll up when they change: the new ones come in from below, the old ones leave above
            ZStack(alignment: .leading) { words.id(key).transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity))) }
                .frame(height: 18).clipped()
                .layoutPriority(1)
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
            Spacer(minLength: 8)
            if live {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(formatCallDuration(max(0, Int(context.date.timeIntervalSince1970 * 1000) - (since ?? group.startedAt))))
                        .font(.scaled(12)).monospacedDigit().foregroundStyle(.tertiary)
                }
            } else {
                if group.added > 0 { Text("+\(group.added)").foregroundStyle(.green) }
                if group.removed > 0 { Text("−\(group.removed)").foregroundStyle(.red) }
                if let ms = group.durationMs { Text(formatCallDuration(ms)).foregroundStyle(.tertiary) }
            }
        }
        .font(.scaled(12, weight: .medium)).monospacedDigit()
        .frame(height: 30)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: key)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: lead)
    }

    /// What the line says now; it is also what rolls when it changes.
    private var key: String { live ? liveLabel : "\(group.title) \(group.summary)" }

    private var liveLabel: String {
        if waiting { return "Waiting for your answer" }
        return group.doing.map { "\($0)…" } ?? "Thinking…"
    }

    @ViewBuilder private var words: some View {
        if live {
            Text(liveLabel).font(.scaled(12.5, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .modifier(Shimmer(active: reduceMotion == false))
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

    private func toggle(_ key: String) {
        if flipped.insert(key).inserted == false { flipped.remove(key) }
    }
}

// MARK: parts

/// How the steps open: the card grows from its line and the steps stay where they are, uncovered from the top as it grows (clipped at
/// the bottom edge), instead of sliding in from above over the line.
private struct RevealLayout: Layout {
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

private struct Reveal: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        RevealLayout(progress: progress) { content }.clipped().opacity(progress)
    }
}

private extension AnyTransition {
    static var reveal: AnyTransition { .modifier(active: Reveal(progress: 0), identity: Reveal(progress: 1)) }
}

private extension Color {
    /// The violet of the agent's thinking.
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
            case .stopped: Image(systemName: "stop.fill").font(.scaled(8)).foregroundStyle(.secondary)
            case .failed: StateMark(shape: .problem, size: 12).foregroundStyle(.red)
            case .none: EmptyView()
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// The spark of thinking: it turns a little and dims, slowly.
private struct Twinkle: View {
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            spark(0, 1)
        } else {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate * 2 * .pi / 2.4
                spark(sin(t) * 18, 0.75 + 0.25 * cos(t))
            }
        }
    }

    private func spark(_ degrees: Double, _ opacity: Double) -> some View {
        Image(systemName: "sparkle").font(.scaled(11, weight: .semibold)).foregroundStyle(Color.thought).rotationEffect(.degrees(degrees)).opacity(opacity)
    }
}

/// The tick a run leaves when it ends: it bounces once.
private struct DoneMark: View {
    @State private var ticks = 0

    var body: some View {
        Image(systemName: "checkmark.circle.fill").font(.scaled(12)).foregroundStyle(.green)
            .symbolEffect(.bounce, options: .nonRepeating, value: ticks)
            .onAppear { ticks += 1 }
    }
}

/// A light that sweeps over the text it is on, in the primary colour over the secondary one the text has.
private struct Shimmer: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                TimelineView(.animation) { context in
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
private struct GlowEdge: View {
    let color: Color
    let waiting: Bool
    let moves: Bool

    var body: some View {
        if moves {
            TimelineView(.animation) { context in
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
        RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.25 + 0.65 * level), lineWidth: 1.2)
            .shadow(color: color.opacity(0.35 * level), radius: 6)
    }

    private func arc(_ degrees: Double) -> some View {
        RoundedRectangle(cornerRadius: 12).strokeBorder(
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
            Image(systemName: "sparkle").font(.scaled(8, weight: .bold)).foregroundStyle(Color.thought)
                .frame(width: 16, height: 16).background(Circle().fill(Color.thought.opacity(0.2))).padding(.top, 3)
            Text(thought.text).font(.scaled(12)).foregroundStyle(.secondary).lineLimit(whole ? nil : 2).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if flipped.insert(key).inserted == false { flipped.remove(key) } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Thought: \(thought.text)")
    }
}

/// One call: what, on what and a short result; a failed call is red. It opens to the diff of a change or the provider's output.
private struct CallRowView: View {
    let key: String
    let call: ToolCall
    @Binding var flipped: Set<String>
    @AppStorage(AppPreferences.toolOutputKey) private var mode = AppPreferences.defaultToolOutput
    @AppStorage(AppPreferences.opensFailedCallsKey) private var opensFailed = AppPreferences.defaultOpensFailedCalls

    var body: some View {
        let open = call.opensByDefault(mode, opensFailed: opensFailed) != flipped.contains(key)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if flipped.insert(key).inserted == false { flipped.remove(key) }
            } label: {
                HStack(spacing: 9) {
                    node
                    Text(call.tool).fontWeight(.medium)
                    Text(call.arg).codeFont(12).lineLimit(1).truncationMode(.middle)
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
            .accessibilityLabel("\(call.tool) \(call.arg), \(call.result.isEmpty ? "running" : call.result)")
            .accessibilityHint(open ? "Hides the detail" : "Shows the detail")
            if open { CallDetailView(call: call).padding(.leading, 25).padding(.bottom, 6) }
        }
    }

    /// The call's node on the rail: its kind, a ring while it goes, red when it failed.
    @ViewBuilder private var node: some View {
        ZStack {
            Circle().fill(call.status == .failed ? Color.red.opacity(0.18) : Color.primary.opacity(0.09))
            if call.status == .running {
                SpinningRing(diameter: 9, lineWidth: 1.3, color: .secondaryLabelColor)
            } else {
                Image(systemName: call.kind.icon).font(.scaled(8, weight: .semibold)).foregroundStyle(call.status == .failed ? Color.red : .secondary)
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
    @AppStorage(AppPreferences.outputLengthKey) private var length = AppPreferences.defaultOutputLength
    @AppStorage(AppPreferences.diffStyleKey) private var diffStyle = AppPreferences.defaultDiffStyle

    var body: some View {
        if call.diff.isEmpty == false {
            DiffView(rows: call.diff, showAll: $showAll, style: diffStyle).clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // the row cuts a long or multi-line command in the middle: opened, the call shows all of it
                if call.kind == .shell, call.arg.contains("\n") || call.arg.count > 80 { CodeBlockView(language: "bash", code: call.arg) }
                if call.output.isEmpty {
                    Text(call.status == .running ? "running…" : "no output").font(.scaled(11.5)).foregroundStyle(.secondary).padding(.horizontal, 6)
                } else {
                    CodeBlockView(language: "Output", code: call.output.joined(separator: "\n"), foldAfter: length.rawValue, spare: 0)
                }
            }
        }
    }
}
