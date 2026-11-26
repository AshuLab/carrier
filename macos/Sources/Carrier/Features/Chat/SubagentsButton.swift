import CarrierCore
import CarrierUI
import SwiftUI

/// The round glass button in a session's header that counts its subagents: two figures and a count, with a turning arc while any launch runs,
/// and a small red dot when nothing runs and at least one failed.
struct SubagentsButton: View {
    let state: SubagentsButtonState
    let spoken: String
    /// Overrides whether the running arc moves; nil follows Reduce Motion.
    var moves: Bool? = nil
    let action: () -> Void

    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .running(let count):
            button(count: count, running: true, failed: false)
        case .quiet(let total, let failed):
            button(count: total, running: false, failed: failed)
        }
    }

    private func button(count: Int, running: Bool, failed: Bool) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s5) {
                Glyph(.users, size: 12)
                Text("\(count)").scaledFont(12, weight: .medium).monospacedDigit()
                if failed {
                    Circle().fill(Color.red).frame(width: 6, height: 6).accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Tokens.Space.s10)
            .frame(height: ToolbarPillButton.height)
            .background(Capsule().fill(Color.primary.opacity(hovered && enabled ? 0.1 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .opacity(enabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .glassEffect(.regular, in: .capsule)
        .overlay {
            if running {
                GlowEdge(color: .thought, waiting: false, moves: moves ?? (reduceMotion == false), cornerRadius: ToolbarPillButton.height / 2)
                    .allowsHitTesting(false)
            }
        }
        .help(spoken)
        .accessibilityLabel(spoken)
    }
}
