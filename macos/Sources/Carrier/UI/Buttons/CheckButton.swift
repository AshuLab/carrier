import CarrierCore
import SwiftUI

/// The button that asks again (Check again, Check now) wherever the app has one, so that they all look alike: at rest it says what it does;
/// while it checks it keeps its size and turns the arrows ("Checking…"); a check the person asked for ends in a green mark and "Up to date", or a
/// red one and "Check failed". The faces share one cell, so the button is as wide as the widest and nothing beside it moves. Its skin is the place's:
/// the window's toolbar (`.toolbar`, the item adds the glass), a row of a form (`.capsule`) or a page's header (`.text`). Which face it wears is `phase`,
/// which the area moves (`CheckAgainButton` does, from a check that runs and ends); a click always runs `action`.
struct CheckButton: View {
    enum Skin { case toolbar, capsule, text }

    /// Resting, running, or showing how the last check ended.
    enum Phase: Equatable { case idle, checking, done, failed }

    var skin = Skin.capsule
    var title = "Check again"
    let phase: Phase
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var words: String {
        switch phase {
        case .idle: title
        case .checking: "Checking…"
        case .done: "Up to date"
        case .failed: "Check failed"
        }
    }

    var body: some View {
        Group {
            switch skin {
            case .capsule:
                Button(action: action) { faces }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).fixedSize()
            case .text:
                Button(action: action) { faces }.buttonStyle(HoverTextButtonStyle(tint: nil))
            case .toolbar:
                Button(action: action) {
                    faces.padding(.horizontal, 11).frame(height: ToolbarPillButton.height)
                        .background(Capsule().fill(Color.primary.opacity(hovered ? 0.1 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain).onHover { hovered = $0 }.animation(.easeOut(duration: 0.12), value: hovered)
            }
        }
        .onChange(of: phase) {
            if phase == .done || phase == .failed { AccessibilityNotification.Announcement(words).post() }
        }
    }

    private var faces: some View {
        ZStack {
            face(.idle) { Glyph(.refresh, size: 12); Text(title) }
            face(.checking) { Glyph(.refresh, size: 12).glyphSpinning(phase == .checking); Text("Checking…") }
            face(.done) { ResultMark(kind: .check, tint: ResultMark.green, shown: phase == .done); Text("Up to date") }
            face(.failed) { ResultMark(kind: .cross, tint: ResultMark.red, shown: phase == .failed); Text("Check failed") }
        }
        .scaledFont(12, weight: .medium)
        .accessibilityElement(children: .ignore).accessibilityLabel(words)
    }

    private func face<Content: View>(_ own: Phase, @ViewBuilder _ content: () -> Content) -> some View {
        let here = phase == own
        return HStack(spacing: 5, content: content)
            .opacity(here ? 1 : 0).offset(y: here || reduceMotion ? 0 : 4).blur(radius: here || reduceMotion ? 0 : 3)
            .animation(.easeOut(duration: 0.18), value: phase)
    }
}

/// The result as a 14 pt disc that pops in and a white mark that draws itself, as the Engine row's `StatusMark` but with a beginning.
private struct ResultMark: View {
    enum Kind { case check, cross }

    /// Deeper than the system's green and red, which a white mark gets lost on at 14 pt.
    static let green = Color(red: 0.11, green: 0.50, blue: 0.26)
    static let red = Color(red: 0.78, green: 0.19, blue: 0.17)

    let kind: Kind
    let tint: Color
    let shown: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(tint).scaleEffect(shown || reduceMotion ? 1 : 0.4).opacity(shown ? 1 : 0)
                .animation(reduceMotion ? nil : .spring(duration: 0.32, bounce: 0.4).delay(0.05), value: shown)
            MarkShape(kind: kind).trim(from: 0, to: shown ? 1 : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.28).delay(0.22), value: shown)
        }
        .frame(width: 14, height: 14)
    }
}

/// The tick or the cross, drawn on a 14 by 14 grid.
private struct MarkShape: Shape {
    let kind: ResultMark.Kind

    func path(in rect: CGRect) -> Path {
        let k = rect.width / 14
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        switch kind {
        case .check:
            path.move(to: at(4, 7.2)); path.addLine(to: at(6.1, 9.2)); path.addLine(to: at(10, 5))
        case .cross:
            path.move(to: at(4.8, 4.8)); path.addLine(to: at(9.2, 9.2))
            path.move(to: at(9.2, 4.8)); path.addLine(to: at(4.8, 9.2))
        }
        return path
    }
}
