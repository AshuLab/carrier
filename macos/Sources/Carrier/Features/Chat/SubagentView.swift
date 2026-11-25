import CarrierCore
import SwiftUI

/// The subagent view (docs/glossary.md): the brief the subagent was given as a bubble with its own label, then its calls, thoughts and messages
/// as flow items, drawn by the views the main agent's are (`FlowItemView`, so the same live line and chip; the rows of a subagent it launched
/// are in its groups and open in turn). It takes `SubagentWork` and not a session, so the epic's slice card can show it from its own items.
/// Nothing can be typed to a subagent: the place of the message box holds `SubagentNote`.
struct SubagentView: View {
    let work: SubagentWork
    /// The window's header says the rest of `work.header`; the note's Back button leaves for the conversation, or the Agent output tab.
    let backToChat: () -> Void
    var backTitle = "Back to chat"
    @State private var flipped: Set<String> = []
    @AppStorage(Preference.chatToolOutput) private var mode
    @AppStorage(Preference.chatShowReasoning) private var showsReasoning
    @AppStorage(Preference.chatMessageSpacing) private var messageSpacing
    @AppStorage(Preference.appearanceMessageWidth) private var messageWidth

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: messageSpacing.gap) {
                if let brief = work.brief { BriefBubble(text: brief) }
                ForEach(visibleFlow(work.items, mode: mode, showsReasoning: showsReasoning)) { FlowItemView(flow: $0, flipped: $flipped) }
            }
            .padding(.horizontal, Tokens.Space.s40).padding(.vertical, Tokens.Space.s16)
            .frame(maxWidth: messageWidth.points, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.top)
        .safeAreaInset(edge: .bottom, spacing: Tokens.Space.none) {
            SubagentNote(backToChat: backToChat, backTitle: backTitle)
                .padding(.horizontal, Tokens.Space.s40).padding(.vertical, Tokens.Space.s12)
                .frame(maxWidth: messageWidth.points).frame(maxWidth: .infinity)
        }
        .scaledFont(13)
        .accessibilityLabel("Subagent \(work.header.title)")
    }
}

/// What the subagent was given, as the person's own message is drawn (a bubble on the right) with a label over it.
private struct BriefBubble: View {
    @Environment(\.pieceTheme) private var theme
    let text: String

    var body: some View {
        VStack(alignment: .trailing, spacing: Tokens.Space.s3) {
            Text("Brief from the main agent").scaledFont(10.5, weight: .semibold).textCase(.uppercase).tracking(0.5).foregroundStyle(.tint)
            Text(text).chatText(bubble: true).textSelection(.enabled)
                .padding(.horizontal, Tokens.Space.s14).padding(.vertical, Tokens.Space.s8)
                .chatSurface(.regular.tint(theme.accent.opacity(0.1)), flat: theme.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: Tokens.Radius.panel))
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, Tokens.Space.bubbleMargin)
        .accessibilityElement(children: .combine)
    }
}

/// The message box's place in a subagent view: the read-only note and the way back to the conversation.
private struct SubagentNote: View {
    let backToChat: () -> Void
    let backTitle: String

    var body: some View {
        HStack(spacing: Tokens.Space.s10) {
            Glyph(.lock, size: 12).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("Subagent work is read-only.").scaledFont(12.5).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            Button(action: backToChat) {
                Label(backTitle, icon: .chevronLeft).scaledFont(12, weight: .medium).labelStyle(.titleAndIcon)
                    .padding(.horizontal, Tokens.Space.s12).frame(height: ToolbarPillButton.height)
                    .chatSurface(.regular.interactive(), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, Tokens.Space.s14).padding(.trailing, Tokens.Space.s10).frame(height: 44)
        .frame(maxWidth: .infinity)
        .workCard()
    }
}
