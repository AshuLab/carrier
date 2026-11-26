import CarrierCore
import CarrierUI
import SwiftUI

/// The subagent view (docs/glossary.md): the brief the subagent was given as a bubble with its own label, then its calls, thoughts and messages
/// as flow items, drawn by the views the main agent's are (`FlowItemView`, so the same live line and chip; the rows of a subagent it launched
/// are in its groups and open in turn). It takes `SubagentWork` and not a session, so the epic's slice card can show it from its own items.
/// Nothing can be typed to a subagent: the place of the message box holds `SubagentNote`.
struct SubagentView: View {
    let work: SubagentWork
    /// The window's header says the rest of `work.header`; the note's Back button leaves for the conversation, or the Agent output tab.
    let backToChat: () -> Void
    var backTitle = Copy.chatSubagentBackToChat()
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
                if let result = work.result {
                    SubagentResultCard(result: result)
                        .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, Tokens.Space.s4)
                }
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
        .accessibilityLabel(Copy.chatSubagentTitleSpoken(title: work.header.title))
    }
}

/// What the subagent was given, as the person's own message is drawn (a bubble on the right) with a label over it.
private struct BriefBubble: View {
    @Environment(\.pieceTheme) private var theme
    let text: String

    var body: some View {
        VStack(alignment: .trailing, spacing: Tokens.Space.s3) {
            Text(Copy.chatSubagentBrief()).scaledFont(10.5, weight: .semibold).textCase(.uppercase).tracking(0.5).foregroundStyle(.tint)
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
            Text(Copy.chatSubagentReadOnly()).scaledFont(12.5).foregroundStyle(.secondary).lineLimit(1)
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

/// What a finished or failed subagent returned, in the view's card: its header ("Result", plus "Failed" when it failed), its `text`
/// folded after six lines when it is long, and "Failed" alone when it failed with no summary.
struct SubagentResultCard: View {
    let result: SubagentResult
    @State private var expanded: Bool
    @State private var overflows = false

    init(result: SubagentResult, startsExpanded: Bool = false) {
        self.result = result
        _expanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.none) {
            header
            if let text = result.text {
                SettingsDivider()
                ResultBodyLayout(expanded: expanded) {
                    ClippedResultBox(expanded: expanded) {
                        MarkdownView(text: text)
                            .padding(.horizontal, Tokens.Space.s12).padding(.vertical, Tokens.Space.s10)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full in
                                let line = ChatText.clamped(CGFloat(AppPreferences().chatTextSize))
                                let six = line * 6 + AppPreferences().chatLineSpacing.extra(forSize: line) * 5 + Tokens.Space.s10 * 2
                                overflows = full > six + 1
                            }
                        sixLinesReference
                    }
                    .clipped()
                    sixLinesReference
                    foldBar
                }
                .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .workCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Copy.chatSubagentResult())
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.s10) {
            if result.failed {
                Disc(color: .red, mark: "!", shape: .problem, size: 16).accessibilityHidden(true)
            } else {
                Disc(color: .green, mark: "✓", shape: .ready, size: 16).accessibilityHidden(true)
            }
            Text(Copy.chatSubagentResult()).scaledFont(12.5, weight: .semibold).foregroundStyle(result.failed ? Color.red : .primary).lineLimit(1)
            Spacer(minLength: Tokens.Space.s8)
            if result.failed {
                Text(Copy.chatFailed()).scaledFont(12, weight: .medium).foregroundStyle(.red).lineLimit(1)
            }
        }
        .padding(.horizontal, Tokens.Space.s10).frame(height: 30)
    }

    private var sixLinesReference: some View {
        let lines = Array(repeating: "1", count: 6).joined(separator: String(UnicodeScalar(10)))
        return Text(lines)
            .chatText()
            .padding(.horizontal, Tokens.Space.s12).padding(.vertical, Tokens.Space.s10)
            .hidden()
            .accessibilityHidden(true)
    }

    private var foldBar: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.none) {
            SettingsDivider()
            Button { flipCard { expanded.toggle() } } label: {
                HStack(spacing: Tokens.Space.s8) {
                    Text(expanded ? Copy.chatSubagentResultShowLess() : Copy.chatSubagentResultShowMore())
                        .scaledFont(12).foregroundStyle(.secondary)
                    Spacer(minLength: Tokens.Space.s8)
                    CardChevron(open: expanded, width: 12)
                }
                .padding(.horizontal, Tokens.Space.s12).frame(height: 30).frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityHidden(overflows == false)
    }
}

/// Clips the result body to six lines while folded and reports its unclipped height when asked with `.greatestFiniteMagnitude`.
private struct ClippedResultBox: Layout {
    let expanded: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let widthProposal = ProposedViewSize(width: proposal.width, height: nil)
        let full = subviews[0].sizeThatFits(widthProposal)
        if proposal.height == .greatestFiniteMagnitude { return full }
        let six = subviews[1].sizeThatFits(widthProposal)
        let overflows = full.height > six.height + 1
        return CGSize(width: full.width, height: (overflows && expanded == false) ? six.height : full.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let widthProposal = ProposedViewSize(width: bounds.width, height: nil)
        let full = subviews[0].sizeThatFits(widthProposal)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: full.height))
        subviews[1].place(at: bounds.origin, anchor: .topLeading, proposal: .zero)
    }
}

/// Lays out `[clippedBox, reference, foldBar]` and includes `foldBar` only when the unclipped body exceeds six lines.
private struct ResultBodyLayout: Layout {
    let expanded: Bool

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let widthProposal = ProposedViewSize(width: proposal.width, height: nil)
        let shown = subviews[0].sizeThatFits(widthProposal)
        let full = subviews[0].sizeThatFits(ProposedViewSize(width: proposal.width, height: .greatestFiniteMagnitude))
        let six = subviews[1].sizeThatFits(widthProposal)
        guard full.height > six.height + 1 else { return shown }
        let bar = subviews[2].sizeThatFits(widthProposal)
        return CGSize(width: max(shown.width, bar.width), height: shown.height + bar.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let widthProposal = ProposedViewSize(width: bounds.width, height: nil)
        let shown = subviews[0].sizeThatFits(widthProposal)
        let full = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: .greatestFiniteMagnitude))
        let six = subviews[1].sizeThatFits(widthProposal)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: shown.height))
        subviews[1].place(at: bounds.origin, anchor: .topLeading, proposal: .zero)
        let overflows = full.height > six.height + 1
        let bar = overflows ? subviews[2].sizeThatFits(widthProposal) : .zero
        subviews[2].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + shown.height),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bar.height)
        )
    }
}
