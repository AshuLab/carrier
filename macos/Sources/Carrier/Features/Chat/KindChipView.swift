import CarrierCore
import SwiftUI

/// The capsule at the start of a live line naming what the agent waits on; long names (e.g. an MCP server) are cut on one line.
struct KindChipView: View {
    let chip: KindChip

    var body: some View {
        CappedWidth(maxWidth: 160) {
            HStack(spacing: Tokens.Space.s4) {
                if let icon = chip.icon {
                    Glyph(icon, size: 9.5)
                }
                Text(chip.label).scaledFont(11, weight: .semibold).lineLimit(1).truncationMode(.tail)
            }
            .foregroundStyle(foreground)
            .padding(.leading, chip.icon == nil ? Tokens.Space.s8 : Tokens.Space.s6).padding(.trailing, Tokens.Space.s8).padding(.vertical, Tokens.Space.s1)
            .background(Capsule().fill(background))
        }
        .fixedSize()
    }

    private var foreground: Color {
        switch chip.tint {
        case .thought: Color(Tokens.ToolCall.thought)
        case .files: Color(Tokens.ToolCall.files)
        case .shell: Color(Tokens.ToolCall.shell)
        case .mcp: Color(Tokens.ToolCall.mcp)
        case .subagents: Color(Tokens.ToolCall.subagents)
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
