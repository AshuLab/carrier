import AppKit
import CarrierCore
import SwiftUI

/// The rows of an open session under its row: the agent's messages, notes and errors as the chat draws them, and each run of its
/// calls as the chat's work card (`ChatToolGroupView`), so the epic and a session read the same. They are the content of a `Section` of the
/// Agent output tab's lazy stack, so only the rows on screen are built. `flipped` is what the person opened or folded, by id, for every card
/// of the tab (the lazy stack recreates rows, so a row does not keep it itself).
struct TranscriptRows: View {
    let content: TranscriptBody
    @Binding var flipped: Set<String>
    @AppStorage(Preference.chatToolOutput) private var mode
    @AppStorage(Preference.chatShowReasoning) private var showsReasoning

    var body: some View {
        switch content {
        case .loading:
            LoadingRow().sessionRow()
        case .items(let items) where items.isEmpty:
            EmptyStateView(state: .noActivity).frame(minHeight: 170).sessionRow()
        case .items(let items):
            ForEach(visibleFlow(items, mode: mode, showsReasoning: showsReasoning)) { FlowItemView(flow: $0, flipped: $flipped).sessionRow() }
        case .tail(let lines):
            MonoLines(lines: lines.isEmpty ? [Copy.chatLogNoOutput()] : lines, monospace: MonospaceStyle.shared.settings)
                .codeFont(12).foregroundStyle(.secondary)
                .textSelection(.enabled).padding(Tokens.Space.s12).sessionRow()
        }
    }
}

/// What a session or the tab shows while its events have not arrived: a spinner and one word, in the place of the rows.
struct LoadingRow: View {
    var body: some View {
        HStack(spacing: Tokens.Space.s8) {
            ProgressView().controlSize(.small)
            Text(Copy.chatLoading()).foregroundStyle(.secondary)
        }
        .scaledFont(12)
        .frame(maxWidth: .infinity, minHeight: 64)
        .accessibilityElement(children: .combine)
    }
}

/// One entry of the log with its margins: the agent's message, a note, an error, a skill, a run of calls as the chat's work card or a slice
/// row (a subagent's own steps are in its view).
struct FlowItemView: View {
    let flow: FlowItem
    @Binding var flipped: Set<String>
    @AppStorage(Preference.chatToolOutput) private var mode
    @AppStorage(Preference.chatOpensFailedCalls) private var opensFailed

    var body: some View {
        switch flow {
        case .message(_, let text):
            Group {
                if let json = jsonMessage(text) { JSONMessageView(message: json) } else { MarkdownView(text: text) }
            }
            .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, Tokens.Space.s8)
        case .note(_, let text):
            if let published = publishedNote(text) {
                PublishedNoteRow(note: published)
            } else {
                Text(text).scaledFont(12).foregroundStyle(.secondary).textSelection(.enabled)
                    .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, Tokens.Space.s6)
            }
        case .error(_, let text):
            FailureBannerView(banner: failedTurnBanner(agent: "", error: text), copyDetails: true, retry: nil)
                .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, Tokens.Space.s6)
        case .skill(_, let call):
            SkillRowView(call: call).padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, Tokens.Space.s4)
        case .tools(let id, let group, let live):
            // the rows of the subagents the run launched (a subagent view's own groups have them; the epic's have none)
            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                ChatToolGroupView(id: "t\(id)", group: group, live: live, startsOpen: mode == .expanded || (opensFailed && group.failed > 0), flipped: $flipped)
                ForEach(group.subagents) { SubagentRowView(subagent: $0) }
            }
            .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, Tokens.Space.s4)
        case .slice(let lane):
            SliceCardView(lane: lane)
                .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, Tokens.Space.s4)
        }
    }
}

/// The disclosure chevron of every row that opens. It turns in 0.12 s, or just jumps under Reduce Motion.
struct LogChevron: View {
    let open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Glyph(.chevronRight, size: 9).foregroundStyle(.tertiary)
            .rotationEffect(.degrees(open ? 90 : 0))
            .animation(LogMetrics.chevronTurn(reduceMotion: reduceMotion).map { .easeOut(duration: $0) }, value: open)
            .frame(width: LogMetrics.chevronColumn)
    }
}

/// The right-hand columns every call row reserves, so a title is cut at the same place whether or not they show: duration 44
/// (right aligned), status 14, chevron 10, 8 apart. A nil `chevron` leaves its slot empty.
struct CallColumns: View {
    let duration: String?
    var failed = false
    let status: ToolStatus
    var chevron: (visible: Bool, open: Bool)?

    var body: some View {
        HStack(spacing: LogMetrics.gap) {
            Text(duration ?? "").scaledFont(11).monospacedDigit().foregroundStyle(failed ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary)).lineLimit(1)
                .frame(width: LogMetrics.durationColumn, alignment: .trailing)
            Group {
                if status != .ok { ToolStatusView(status: status).scaledFont(14) }
            }
            .frame(width: LogMetrics.statusColumn, height: LogMetrics.statusColumn)
            LogChevron(open: chevron?.open == true).opacity(chevron?.visible == true ? 1 : 0)
        }
    }
}

/// A code change the agent published ("created 946 (the-branch)"): a quiet line with the verb, the pull request as a link and the
/// branch cut in the middle, its whole name in the tooltip.
struct PublishedNoteRow: View {
    let note: PublishedNote
    @Environment(\.epicRepo) private var repo

    var body: some View {
        HStack(spacing: Tokens.Space.s6) {
            Glyph(.gitPullRequest, size: 10).foregroundStyle(.tertiary)
            Text(note.verb).foregroundStyle(.secondary)
            if let number = note.number {
                PullRequestChip(number: number, dot: nil, url: repo.map { "https://github.com/\($0)/pull/\(number)" })
            } else {
                Text(note.identifier).foregroundStyle(.secondary)
            }
            if let branch = note.branch {
                Text(branch).codeFont(11).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle).help(branch)
            }
            Spacer(minLength: 0)
        }
        .scaledFont(12).lineLimit(1)
        .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, Tokens.Space.s6)
        .accessibilityElement(children: .combine)
    }
}

/// A call to the `Skill` tool, a milestone of its own: one line of the work card's family (its tile, "Skill", the skill's name, how long
/// it took), with nothing to open.
struct SkillRowView: View {
    let call: ToolCall

    private var failed: Bool { call.status == .failed }

    var body: some View {
        HStack(spacing: LogMetrics.gap) {
            Glyph(call.kind.icon, size: 9, bold: true).foregroundStyle(.white)
                .frame(width: LogMetrics.iconWidth, height: LogMetrics.iconWidth).background(RoundedRectangle(cornerRadius: Tokens.Radius.small).fill(call.kind.color))
            Text(Copy.chatSkill()).fontWeight(.semibold).foregroundStyle(failed ? Color.red : .primary)
            Text(call.arg).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if failed { Text(Copy.chatResultFailed()).foregroundStyle(.red) } else if let ms = call.durationMs { Text(formatCallDuration(ms)).foregroundStyle(.tertiary).monospacedDigit() }
        }
        .scaledFont(12.5).lineLimit(1)
        .padding(.horizontal, Tokens.Space.s10).frame(height: LogMetrics.skillRow)
        .workCard()
        .help(call.arg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(callAccessibilityLabel(call))
    }
}


/// How a call that did not simply work is marked: a red disc with a white cross, or a spinner while it runs (still under Reduce
/// Motion). The disc is drawn in two colours: with one, the mark would be see-through. VoiceOver skips both: the row's label says it.
struct ToolStatusView: View {
    let status: ToolStatus

    var body: some View {
        Group {
            if status == .pending {
                SpinningRing(diameter: 12, lineWidth: 1.5, color: .secondaryLabelColor)
            } else if status == .error, let icon = status.icon {
                Glyph(icon, size: 12).foregroundStyle(Color.red)
            }
        }
        .accessibilityHidden(true)
    }
}

extension ToolKind {
    /// The colour of the icon box of a milestone: blue for an edit, grey for a skill. The calls have a bare glyph.
    var color: Color {
        switch self {
        case .edit: .blue
        case .read, .search, .shell, .other, .mcp: Color(Tokens.Milestone.plain)
        }
    }
}
