import CarrierCore
import SwiftUI

/// Where a `/clear` emptied the agent's context, in the feed, under the person's own `/clear`: a fine line across and on it a glass capsule that says the context
/// was cleared and how much it freed; under it, quieter, what that means (the messages stay to read, the agent no longer has them). The same anatomy as
/// `AgentSwitchDivider`, which this reads like: a cut in the conversation, not a line of statistics.
struct ClearedDivider: View {
    let freed: Double?
    /// The agent's short name, as the capsule of a change of agent writes it.
    let agent: String

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 12) {
                line
                HStack(spacing: 9) {
                    Glyph(.brush, size: 12).foregroundStyle(Color.themeAccent).accessibilityHidden(true)
                    Text("Context cleared").font(.scaled(12, weight: .semibold)).lineLimit(1)
                    if let freedText {
                        Rectangle().fill(Color.primary.opacity(0.2)).frame(width: 1, height: 12).accessibilityHidden(true)
                        Text(freedText).font(.scaled(11.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .chatSurface(.regular, flat: Color.primary.opacity(0.07), in: Capsule())
                line
            }
            Text(clearedDetail(agent: agent)).font(.scaled(11.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled).padding(.horizontal, 24)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(["Context cleared", freedText, clearedDetail(agent: agent)].compactMap { $0 }.joined(separator: ". "))
    }

    private var freedText: String? { clearedFreedText(freed) }

    private var line: some View { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1) }
}
