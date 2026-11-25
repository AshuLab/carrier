import CarrierCore
import SwiftUI

/// Where the agent's context was cut, in the feed, under the person's own command (`/clear`, `/compact`) or alone when the agent did it by itself (auto-compact): a fine line across and on it a
/// glass capsule with what happened and, after it, what that came to (tokens freed, the sizes before and after); under it, quieter, what that means for the agent. The same anatomy as
/// `AgentSwitchDivider`, which this reads like: a cut in the conversation, not a line of statistics. A failure is the same cut in red.
struct ContextCutDivider: View {
    @Environment(\.pieceTheme) private var theme
    let glyph: AppIcon
    let title: String
    /// What the capsule says beside its title, each after a thin bar.
    let notes: [String]
    let detail: String
    var failed = false

    var body: some View {
        VStack(spacing: Tokens.Space.s8) {
            HStack(spacing: Tokens.Space.s12) {
                line
                HStack(spacing: Tokens.Space.s10) {
                    Glyph(glyph, size: 12).foregroundStyle(failed ? Color.red : theme.accent).accessibilityHidden(true)
                    Text(title).scaledFont(12, weight: .semibold).foregroundStyle(failed ? Color.red : Color.primary).lineLimit(1)
                    ForEach(notes, id: \.self) { note in
                        Rectangle().fill(Color.primary.opacity(0.2)).frame(width: 1, height: 12).accessibilityHidden(true)
                        Text(note).scaledFont(11.5).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.horizontal, Tokens.Space.s14).padding(.vertical, Tokens.Space.s6)
                .chatSurface(.regular, flat: Color.primary.opacity(0.07), in: Capsule())
                line
            }
            Text(detail).scaledFont(11.5).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(.horizontal, Tokens.Space.s24)
        }
        .padding(.vertical, Tokens.Space.s6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(([title] + notes + [detail]).joined(separator: ". "))
    }

    private var line: some View { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1) }
}
