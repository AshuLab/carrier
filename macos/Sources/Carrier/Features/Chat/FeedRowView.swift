import CarrierCore
import SwiftUI

/// A row of the feed. It is `Equatable`, used with `.equatable()`: SwiftUI leaves a row that is `==` to the one it has alone, and that is nearly
/// every row at each poll while the agent writes. A new input of the row has to be added to `==` below, or a change of it is not drawn.
struct FeedRowView: View, Equatable {
    let row: FeedRow
    /// When the message was written, in ms; nil for a row that is not a stored message.
    let time: Int?
    /// What the turn that ended on this message says of itself (the model, how long, the tokens), shown on hover.
    let summary: TurnSummary?
    /// Whether the footer stays in view without the pointer: the last answer of the conversation.
    let pinned: Bool
    /// What the person flipped, to write: the row is drawn from `flippedHere` (its own keys), which is what is compared.
    @Binding var flipped: Set<String>
    let flippedHere: Set<String>
    let agent: String
    /// What the session lists, to show the commands a message names as pills.
    let commands: [ChatCommand]
    /// Whether this is the stopped or failed turn the person can still act on: Continue and Try again show only there.
    let offersWayOut: Bool
    /// What a run of the agent's work needs to know to draw itself: whether it is the one working now.
    let work: WorkState
    @Environment(\.feedActions) private var actions
    @AppStorage(Preference.chatMessageTimes) private var messageTimes
    @State private var hovering = false
    @State private var copied = false
    @State private var overCopy = false

    init(row: FeedRow, time: Int?, summary: TurnSummary?, pinned: Bool, flipped: Binding<Set<String>>, agent: String, commands: [ChatCommand], offersWayOut: Bool, work: WorkState) {
        (self.row, self.time, self.summary, self.pinned, self.agent, self.commands, self.offersWayOut, self.work) = (row, time, summary, pinned, agent, commands, offersWayOut, work)
        _flipped = flipped
        flippedHere = flippedKeys(of: row.id, in: flipped.wrappedValue)
    }

    // everything the body draws from; `actions`, `messageTimes` and the other states and defaults of the row invalidate it by themselves
    static func == (a: Self, b: Self) -> Bool {
        a.row == b.row && a.time == b.time && a.summary == b.summary && a.pinned == b.pinned && a.flippedHere == b.flippedHere && a.agent == b.agent
            && a.commands == b.commands && a.offersWayOut == b.offersWayOut && a.work == b.work
    }

    var body: some View {
        switch row {
        case .user(_, let text):
            // the files that came with it are chips over the bubble, and the bubble is what the person wrote
            let attached = splitAttachments(text)
            let split = splitPastes(attached.text)
            let sent = (paths: attached.paths, text: split.text, pastes: split.pastes)
            VStack(alignment: .trailing, spacing: 8) {
                if sent.paths.isEmpty == false { SentAttachments(paths: sent.paths).padding(.bottom, 3) }
                if sent.pastes.isEmpty == false {
                    VStack(alignment: .trailing, spacing: 6) {
                        ForEach(Array(sent.pastes.enumerated()), id: \.offset) { _, pasted in PastedTextCard(text: pasted).frame(maxWidth: 440) }
                    }
                    .padding(.bottom, 3)
                }
                if sent.text.isEmpty == false {
                    messageText(sent.text, commands: commands).chatText(bubble: true).textSelection(.enabled)
                        .padding(.horizontal, 13).padding(.vertical, 8)
                        .chatSurface(.regular.tint(Color.themeAccent.opacity(0.1)), flat: Color.themeAccent.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
                }
                footer(text, summary: nil, asks: false)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 120)
            .onHover { hovering = $0 }
        case .agent(_, let text, let inProgress):
            VStack(alignment: .leading, spacing: 10) {
                MarkdownView(text: text)
                // the cursor takes the footer's height, so the answer does not grow when it ends and the footer takes its place
                if inProgress { Text("▍").foregroundStyle(.secondary).frame(height: 24, alignment: .leading) }
                if inProgress == false { footer(text, summary: summary, asks: true) }
            }
            .onHover { hovering = $0 }
        case .turnEnd(_, let summary):
            Text(summary.text).font(.scaled(12)).foregroundStyle(.secondary).textSelection(.enabled)
        case .tools(let id, let group):
            // a subagent keeps the line live while it runs, after the turn that launched it ended too
            VStack(alignment: .leading, spacing: 6) {
                ChatToolGroupView(id: id, group: group, live: work.live || group.runningSubagents > 0, waiting: work.waiting, since: work.since, flipped: $flipped)
                ForEach(group.subagents) { SubagentRowView(subagent: $0) }
            }
        case .approval:
            EmptyView() // drawn over the message box, never in the feed (`visibleFeed`)
        case .decided(_, let text, let allow):
            ApprovalDecidedView(text: text, allow: allow)
        case .line(_, let text):
            Text(text).codeFont(12).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
        case .switched(_, let switched):
            AgentSwitchDivider(switched: switched)
        case .cleared(_, let freed):
            ContextCutDivider(glyph: .brush, title: "Context cleared", notes: [clearedFreedText(freed)].compactMap { $0 }, detail: clearedDetail(agent: ProviderIdentityStore.shared.shortName(of: agent)))
        case .compacted(_, let cut):
            ContextCutDivider(glyph: cut.error == nil ? .arrowsMinimize : .warning, title: cut.title, notes: [cut.sizes, cut.saved].compactMap { $0 },
                              detail: cut.detail(agent: ProviderIdentityStore.shared.shortName(of: agent)), failed: cut.error != nil)
        case .error(_, let text):
            FailureBannerView(banner: failedTurnBanner(agent: ProviderIdentityStore.shared.shortName(of: agent), error: text), agent: agent, copyDetails: true, retry: offersWayOut ? actions.retry : nil)
        case .stopped:
            HStack(spacing: 6) {
                Text("\u{25A0} You stopped this turn").foregroundStyle(.secondary)
                if offersWayOut { Button("Continue", action: actions.continueTurn).buttonStyle(.link) }
            }
            .font(.scaled(12))
        }
    }
}

extension FeedRowView {
    /// Under a message: the copy button, its time and, for an agent message, what the turn that ended on it says of itself (the model as a
    /// chip, how long, the tokens). The row is the same height with or without them, so showing them moves nothing; they fade in and out.
    fileprivate func footer(_ text: String, summary: TurnSummary?, asks: Bool) -> some View {
        // the copy button is AppKit's: the pointer over it can end the row's hover, so over the button it keeps the footer up itself, and the button
        // stays hit-testable (it is only ever reached from inside the row, where the footer is already up)
        let shown = hovering || overCopy || pinned || copied
        return HStack(spacing: 14) {
            copyControl(text, asks: asks).opacity(shown ? 1 : 0)
            stamp(shown: shown)
            if let summary { summaryView(summary).opacity(shown ? 1 : 0) }
        }
        .frame(height: 24)
        .animation(.easeInOut(duration: 0.18), value: shown)
    }

    private func summaryView(_ summary: TurnSummary) -> some View {
        let numbers = [summary.duration, summary.contextText, summary.output.map { "\(TurnSummary.tokens($0)) out" }]
            .compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 10) {
            if let model = summary.shortModel {
                // an account that was given an icon, a color or a label says so here; one with none shows the model alone, as it always did
                let identity = ProviderIdentityStore.shared.identity(of: agent)
                HStack(spacing: 5) {
                    if identity != .none {
                        AccountMark(account: agent, size: 11)
                        if let label = identity.label {
                            Text(label).fontWeight(.semibold)
                            Text("·")
                        }
                    }
                    Text(model)
                }
                .font(.scaled(11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Color.secondary.opacity(0.14)))
                .help([identity.label == nil ? nil : agent, summary.model ?? model].compactMap { $0 }.joined(separator: " · "))
            }
            if numbers.isEmpty == false {
                Text(numbers).font(.scaled(12)).foregroundStyle(Color.secondary.opacity(0.8)).help(breakdown(summary))
            }
        }
    }

    /// The tooltip of the numbers: the context at the end of the turn, then what all its model calls read and wrote added up (each call reads the whole
    /// context again, most of it from the cache, so these are many times the context).
    private func breakdown(_ summary: TurnSummary) -> String {
        let total = [("New input", summary.input), ("Read from the cache", summary.cacheRead), ("Written to the cache", summary.cacheWrite), ("Output", summary.output)]
            .compactMap { name, count in count.map { "\(name): \(Int($0).formatted())" } }
        let context = summary.contextTokens.map { ["Context at the end: \(Int($0).formatted())"] } ?? []
        let header = total.isEmpty ? [] : [context.isEmpty ? "All the turn's model calls:" : "\nAll the turn's model calls:"]
        return (context + header + total).joined(separator: "\n")
    }

    /// Copies the message as it was written (its Markdown) and says so with a green tick for a moment. An agent message also offers its plain text, with the
    /// Markdown marks taken out, from the menu next to the button.
    @ViewBuilder private func copyControl(_ text: String, asks: Bool) -> some View {
        let label = Glyph(copied ? .check : .copy, size: 12).foregroundStyle(copied ? Color.green : Color.secondary)
            .frame(width: 26, height: 22)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(overCopy ? 0.16 : 0)))
        .contentShape(RoundedRectangle(cornerRadius: 6))
        Group {
            if asks {
                Menu {
                    Button("Copy as Markdown") { copy(text) }
                    Button("Copy as plain text") { copy(plainText(text)) }
                } label: { label } primaryAction: { copy(text) }
                    .menuStyle(.button).menuIndicator(.hidden)
            } else {
                Button { copy(text) } label: { label }
            }
        }
        .buttonStyle(.plain).fixedSize()
        .onHover { overCopy = $0 }
        .help("Copy message").accessibilityLabel("Copy message")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    /// The text with the inline marks (bold, links, code ticks) read and dropped; the line breaks and the code blocks stay as they are.
    private func plainText(_ markdown: String) -> String {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)).map { String($0.characters) } ?? markdown
    }

    @ViewBuilder fileprivate func stamp(shown: Bool) -> some View {
        if let time { MessageTimeLabel(ms: time, mode: messageTimes, hovering: shown) }
    }
}

/// The time a message was written, in the General format. On hover it keeps its place and only fades in, so the rows do not jump.
struct MessageTimeLabel: View {
    let ms: Int
    let mode: MessageTimes
    let hovering: Bool
    private let timeChanges = TimeFormatChanges()

    var body: some View {
        if mode != .never {
            // a relative time ages while the row stays on screen
            TimelineView(.everyMinute) { context in
                Text(timeText(Date(ms: ms), now: context.date, format: timeChanges.format)).font(.scaled(12)).monospacedDigit().foregroundStyle(.secondary)
                    .opacity(mode.shows(hovering: hovering) ? 1 : 0)
            }
        }
    }
}

/// What a run of the agent's work draws itself from: whether it is the one working now, whether an approval holds it, when the turn began.
struct WorkState: Equatable {
    let live: Bool
    let waiting: Bool
    let since: Int?
}

/// What a row asks of the conversation (Continue, Try again), handed down the environment. It is the same value at every pass: it holds the
/// model and two are equal when they hold the same one, where a closure made at each pass would differ every time and invalidate every row that
/// reads it. Where a row is only shown (the Settings preview) there is no model and the actions do nothing.
struct FeedActions: Equatable {
    let model: ConversationModel?

    func continueTurn() { if let model { Task { await model.continueTurn() } } }
    func retry() { if let model { Task { await model.retry() } } }

    static func == (a: Self, b: Self) -> Bool { a.model === b.model }
}

private struct FeedActionsKey: EnvironmentKey { static let defaultValue = FeedActions(model: nil) }

extension EnvironmentValues {
    var feedActions: FeedActions {
        get { self[FeedActionsKey.self] }
        set { self[FeedActionsKey.self] = newValue }
    }
}
