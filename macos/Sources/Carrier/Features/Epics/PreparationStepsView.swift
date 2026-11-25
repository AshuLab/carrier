import CarrierCore
import SwiftUI

/// The preparation of a session at the top of its conversation, as one card of glass that keeps its shape while it changes what it says: the
/// step it is on as the title with how many there are, segments for the steps, git's progress while a clone runs, and the list of all of them,
/// the ones to come dim. It says so when the agent takes long to answer, shows the reason on the step that failed, and offers Cancel, or Try again.
struct PreparationStepsView: View {
    let steps: [StepRow]
    let preparation: ChatSession.Preparation?
    /// What the host refused when asked to try again or to cancel, in words.
    let refusal: String?
    let retry: () -> Void
    let cancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// When the step it is on began, for the time it shows and for saying it is slow.
    @State private var since = Date()
    @State private var pulse = false

    /// An agent that has not answered in this long is slow: it is busy, or not signed in.
    private static let slowAfter: TimeInterval = 20
    private static let timerAfter: TimeInterval = 5

    private var items: [OutlineItem] { preparationOutline(steps) }
    private var current: OutlineItem? { items.first { $0.status == .running || $0.status == .failed } }
    private var failed: Bool { preparation == .failed || current?.status == .failed }
    /// Changes when the step it is on does, or how it stands.
    private var key: String { "\(current?.id ?? "")-\(current?.status?.rawValue ?? "")" }

    var body: some View {
        TickingTimeline(every: 1) { context in
            card(elapsed: context.date.timeIntervalSince(since))
        }
        .onChange(of: key, initial: true) { since = Date() }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: items)
    }

    private func card(elapsed: TimeInterval) -> some View {
        let slow = failed == false && current?.step == "message" && elapsed >= Self.slowAfter
        return VStack(alignment: .leading, spacing: Tokens.Space.md) {
            HStack(spacing: Tokens.Space.md) {
                badge(slow: slow)
                VStack(alignment: .leading, spacing: Tokens.Space.hair) {
                    Text(title(slow: slow, elapsed: elapsed)).fontWeight(.semibold).contentTransition(.opacity)
                    Text(subtitle(slow: slow)).font(.scaled(11)).foregroundStyle(failed ? Color.red : .secondary).fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                switch preparation {
                case .failed: Button("Try again", action: retry).buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(.small)
                case .running:
                    // its shape shows on hover; the shape reaches a little into the card's margin so the word keeps its place near the edge
                    Button(action: cancel) { Text("Cancel").padding(.horizontal, Tokens.Space.snug).padding(.vertical, Tokens.Space.tight).contentShape(Rectangle()) }
                        .buttonStyle(HoverFillButtonStyle()).foregroundStyle(.secondary).padding(.trailing, -Tokens.Space.xs)
                case nil: EmptyView()
                }
            }
            segments(slow: slow)
            if let progress = current?.progress { clone(progress) }
            VStack(alignment: .leading, spacing: Tokens.Space.tight) {
                ForEach(items) { item in
                    row(item).transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            if let refusal { Text(refusal).font(.scaled(11)).foregroundStyle(.red).textSelection(.enabled) }
        }
        .font(.scaled(12)).padding(Tokens.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // glass, as the notices of the session: the conversation under it is blurred and not seen through it
        .chatSurface(.regular.tint(Color.themeAccent.opacity(0.15)), flat: Color.themeAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .accessibilityElement(children: .contain)
    }

    private func title(slow: Bool, elapsed: TimeInterval) -> String {
        guard let current else { return "Preparing the session…" }
        if slow { return "Still waiting for the agent · \(clock(elapsed))" }
        if failed == false, elapsed >= Self.timerAfter { return "\(current.line) · \(clock(elapsed))" }
        return current.line
    }

    private func subtitle(slow: Bool) -> String {
        if failed { return current?.reason ?? "The preparation stopped." }
        if slow { return "It usually answers in a few seconds. It may be busy, or not signed in." }
        guard let current, let index = items.firstIndex(of: current) else { return "Getting everything ready" }
        let clone = current.step == "clone" ? " · only this first time" : ""
        return "Step \(index + 1) of \(items.count)\(clone)"
    }

    private func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }

    /// The badge of the notices: white on the accent a little deepened with a faint rim of light; red when failed, amber when slow.
    private func badge(slow: Bool) -> some View {
        let fill: Color = failed ? Color.red.mix(with: .black, by: 0.2) : slow ? Color.orange.mix(with: .black, by: 0.15) : Color.themeAccent.mix(with: .black, by: 0.18)
        return Group {
            if failed {
                Glyph(.exclamation, size: 14)
            } else if slow {
                Glyph(.clock, size: 14)
            } else {
                ProgressView().controlSize(.small).colorScheme(.dark)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 30, height: 30)
        .background {
            RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(fill)
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.control).strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
        }
        .accessibilityHidden(true)
    }

    /// A segment a step: done in green, the one it is on in the accent and breathing, a failed one red, the rest dim.
    private func segments(slow: Bool) -> some View {
        HStack(spacing: Tokens.Space.xs) {
            ForEach(items) { item in
                Capsule().fill(color(item, slow: slow)).frame(height: 3)
                    .opacity(item.status == .running && pulse ? 0.45 : 1)
            }
        }
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = reduceMotion == false }
        .accessibilityHidden(true)
    }

    private func color(_ item: OutlineItem, slow: Bool) -> Color {
        switch item.status {
        case .done: .green
        case .running: slow ? .orange : Color.themeAccent
        case .failed: .red
        case nil: Color.primary.opacity(0.14)
        }
    }

    /// git's own line while a clone runs, with how far it is when the line says.
    private func clone(_ progress: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.tight) {
            if let fraction = progressFraction(progress) {
                ProgressView(value: fraction).progressViewStyle(.linear).tint(Color.themeAccent)
            }
            Text(progress).font(.scaled(11).monospacedDigit()).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .transition(.opacity)
    }

    private func row(_ item: OutlineItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.sm) {
            mark(item.status).frame(width: 16)
            if let icon = item.icon { Glyph(icon, size: 12).foregroundStyle(.secondary) }
            Text(item.line).foregroundStyle(item.status == nil ? AnyShapeStyle(.tertiary) : item.status == .done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func mark(_ status: StepRow.Status?) -> some View {
        switch status {
        case .running: ProgressView().controlSize(.mini)
        case .done: Glyph(.checkCircleFilled).foregroundStyle(.green)
        case .failed: Glyph(.closeCircleFilled).foregroundStyle(.red)
        case nil: Glyph(.circle).foregroundStyle(.tertiary)
        }
    }
}
