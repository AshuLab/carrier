import CarrierCore
import SwiftUI

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
