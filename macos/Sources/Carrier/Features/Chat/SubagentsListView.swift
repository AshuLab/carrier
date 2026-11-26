import CarrierCore
import CarrierUI
import SwiftUI

/// The list opened by the header's Subagents button: every subagent of the session as 30 pt rows, in the order the model gives,
/// closing the list and opening that subagent's view when a row is tapped.
struct SubagentsListPopover: View {
    let list: SubagentsList
    /// The time the timers read instead of the clock; a test sets it.
    var clock: Date?
    let select: (String) -> Void
    @State private var contentHeight: CGFloat = 0

    static let width: CGFloat = 520
    static let maxHeight: CGFloat = 400

    private var items: [Subagent] { list.allSubagents }

    private var estimatedHeight: CGFloat {
        let rows = CGFloat(items.count) * 30
        let gaps = CGFloat(max(0, items.count - 1)) * Tokens.Space.s2
        return rows + gaps + Tokens.Space.s8 * 2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                ForEach(items) { subagent in
                    SubagentsListRow(subagent: subagent, clock: clock) {
                        select(subagent.id)
                    }
                }
            }
            .padding(Tokens.Space.s8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.width)
        .frame(height: min(contentHeight > 0 ? contentHeight : estimatedHeight, Self.maxHeight))
        .accessibilityLabel(Copy.chatSubagentsListSpoken())
    }
}

/// One row of the Subagents list: 30 pt high with the shared line content, spinner while running, dimmed with no tick when finished,
/// a red dot (or state mark when states are told apart by shape) when failed, and dimmed saying Stopped when stopped.
struct SubagentsListRow: View {
    let subagent: Subagent
    var clock: Date?
    let action: () -> Void
    @Environment(\.pieceTheme) private var theme

    private var isDimmed: Bool {
        subagent.status == .completed || subagent.status == .stopped
    }

    var body: some View {
        HoverRow(action: action) { _ in
            SubagentLine(subagent: subagent, clock: clock, showsChevron: true, dimmed: isDimmed) {
                lead
            }
        }
        .accessibilityHint(Copy.chatSubagentOpensHint())
    }

    @ViewBuilder private var lead: some View {
        switch subagent.status {
        case .running:
            SpinningRing(diameter: 11, lineWidth: 1.5, color: .secondaryLabelColor)
        case .completed:
            Color.clear
        case .failed:
            if theme.statesByShape {
                StateMark(shape: .problem, size: 12).foregroundStyle(.red)
            } else {
                Circle().fill(Color.red).frame(width: 7, height: 7)
            }
        case .stopped:
            Glyph(.stopFilled, size: 8).foregroundStyle(.secondary)
        }
    }
}
