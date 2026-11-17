import AppKit
import CarrierCore
import SwiftUI

/// An epic's centre: the pipeline fixed on top as a safe-area bar (the content scrolls under it, blurred), then the header
/// and the two tabs. `reply`, `filesChanged` and `sessions` are empty until the window gets them from the engine.
struct EpicView: View {
    let subject: EpicSubject
    let reply: EpicReply?
    let filesChanged: Int
    let sessions: SessionList
    @Binding var folds: SessionFolds
    /// The subagent views open over the tab, the window's (`WindowShell.subagents`; a slice card opens the one of its lane), and what the
    /// window's header says of it.
    @Binding var subagents: [String]
    @Binding var subagentHeader: SubagentHeader?
    /// The `files` reply, once the window asks for it.
    var files: FilesReply?
    /// What a queued epic will do; nil for any other.
    var plan: QueuedPlan?
    /// The reason and the Resume button of a stopped epic, with the store that remembers a Resume in flight; nil for any other.
    var resume: (card: ResumeCard, store: EpicStore)?
    /// The file rows that are open and their fragments; nil when the engine cannot be asked (the rows do not open).
    var fileDiffs: FileDiffs?
    var onContinueInTerminal: (SessionSection, ValidResume) -> Void = { _, _ in }
    /// The width the person chose for the chat's column: the Agent output and the pipeline follow it.
    @AppStorage(AppPreferences.messageWidthKey) private var messageWidth = AppPreferences.defaultMessageWidth
    @State private var tab = EpicTab.agentOutput
    /// Whether the page is at its end: a session that starts scrolls it into view only then, so reading further up is not interrupted.
    @State private var atEnd = true

    var body: some View {
        let work = subagents.last.flatMap { subagentWork(lane: $0, in: sessions, epic: epicHeader(subject, reply: reply).title) }
        ScrollViewReader { page in
            scroll
                // the sessions run oldest to newest: the page opens on the newest, and follows a new one while it sits at the end
                .defaultScrollAnchor(tab == .agentOutput ? .bottom : nil, for: .initialOffset)
                .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.containerSize.height >= $0.contentSize.height - 60 } action: { _, now in
                    atEnd = now
                }
                .onChange(of: tab, initial: true) { fileDiffs?.shown.wrappedValue = tab == .filesChanged }
                .onChange(of: sessions.sections.last?.id) {
                    if atEnd, tab == .agentOutput { withAnimation { page.scrollTo(SessionSectionsView.endID, anchor: .bottom) } }
                }
        }
        // the tab stays under the subagent view, so Back finds it as it was; nothing under it takes keys or taps
        .disabled(subagents.isEmpty == false)
        .accessibilityHidden(subagents.isEmpty == false)
        .overlay {
            if let work {
                SubagentView(work: work, backToChat: { subagents = [] }, backTitle: "Back to Agent output")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.themeWindow)
            }
        }
        .environment(\.openSubagent) { subagents = [$0] }
        // a card whose lane is gone leaves no view open
        .onChange(of: work?.header, initial: true) { _, shown in
            subagentHeader = shown
            if shown == nil { subagents = [] }
        }
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                EpicHeaderView(header: epicHeader(subject, reply: reply))
                UnderlineTabs(
                    items: EpicTab.allCases.map { item in
                        let files = max(filesChanged, filesChangedCount(files))
                        return UnderlineTabs.Item(id: item, title: item.title, icon: item.icon, count: item == .filesChanged && files > 0 ? "\(files)" : nil)
                    },
                    selection: $tab
                )
                tabContent
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .safeAreaBar(edge: .top) {
            PipelineStrip(steps: pipelineSteps(subject, reply: reply))
                .frame(maxWidth: messageWidth.points).frame(maxWidth: .infinity)
                .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .agentOutput:
            VStack(alignment: .leading, spacing: 18) {
                agentFeed
                if let resume { ResumeCardView(card: resume.card, store: resume.store, epic: EpicRef(repo: subject.repo, issue: subject.issue)) }
            }
            .frame(maxWidth: messageWidth.points).frame(maxWidth: .infinity)
        case .filesChanged:
            FilesChangedView(files: files, fileDiffs: fileDiffs)
        }
    }

    @ViewBuilder private var agentFeed: some View {
        if let empty = subject.outputEmptyState {
            EmptyStateView(state: empty).frame(minHeight: 260)
            if let plan { QueuedPlanView(plan: plan) }
        } else if sessions.loaded == false {
            LoadingStateView(title: "Loading activity", line: "Reading what the agents did on this epic.").frame(minHeight: 260)
        } else if sessions.sections.isEmpty {
            if case .active(let epic) = subject, isStarting(epic) {
                StartingView(epic: epic, reply: reply)
            } else {
                EmptyStateView(state: .noActivity).frame(minHeight: 260)
            }
        } else {
            SessionSectionsView(
                epic: EpicRef(repo: subject.repo, issue: subject.issue),
                list: sessions,
                reply: reply,
                folds: $folds,
                onContinueInTerminal: onContinueInTerminal
            )
        }
    }
}

/// The title block: the state's glyph centred beside the title, and under it a pill with the state in words, the repository and
/// the issue as chips, and the labels. The PR is not here, the toolbar has it.
private struct EpicHeaderView: View {
    let header: EpicHeader

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HeaderGlyph(state: header.state)
            VStack(alignment: .leading, spacing: 8) {
                Text(header.title).font(.title2.weight(.bold)).lineLimit(2)
                FlowLayout(spacing: 8) {
                    StatePill(state: header.state, text: header.status)
                    if let url = URL(string: "https://github.com/\(header.repo)") {
                        Button { NSWorkspace.shared.open(url) } label: { Chip(text: header.repo, mark: GitHubMark.image, opens: true) }
                            .buttonStyle(.plain).help("Open the repository")
                    }
                    if let url = browserURL(header.issueURL) {
                        Button { NSWorkspace.shared.open(url) } label: { Chip(text: "#\(header.issue)", mark: nil, opens: true) }
                            .buttonStyle(.plain).help("Open the issue")
                    }
                    ForEach(header.labels, id: \.self) { label in
                        Text(label).font(.scaled(12, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
            }
        }
    }
}

/// The state's glyph at header size: a ring that turns, an orange disc with a mark, a hollow circle or a blue disc with a tick.
private struct HeaderGlyph: View {
    let state: EpicMenuState

    var body: some View {
        Group {
            switch state {
            case .running: SpinningRing(diameter: 26, lineWidth: 3)
            case .needsYou: disc(.orange, "!", state.shape())
            case .ready: disc(.blue, "✓", .ready)
            case .done: disc(.green, "✓", nil)
            case .cancelled: disc(.gray, "✕", nil)
            case .waiting: Circle().strokeBorder(Color.gray, lineWidth: 3).frame(width: 24, height: 24)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    private func disc(_ color: Color, _ mark: String, _ shape: StateShape?) -> some View {
        Disc(color: color, mark: mark, shape: shape, size: 30)
    }
}

private struct StatePill: View {
    let state: EpicMenuState
    let text: String
    @AppStorage(AppPreferences.statesByShapeKey) private var byShape = false

    var body: some View {
        let color: Color = switch state {
        case .running: .green
        case .needsYou: .orange
        case .ready: .blue
        case .waiting, .cancelled: .gray
        case .done: .green
        }
        HStack(spacing: 6) {
            if byShape, let shape = state.shape() {
                Image(systemName: stateSymbol(shape)).font(.scaled(11, weight: .bold))
            } else {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(text).lineLimit(1).truncationMode(.tail)
        }
        .font(.scaled(12, weight: .semibold)).foregroundStyle(color)
        .help(text)
        .padding(.horizontal, 11).padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.2)))
    }
}

/// A pill of the header; one that opens GitHub ends in the arrow of an external link, and the repository's starts with its mark.
private struct Chip: View {
    let text: String
    let mark: Image?
    let opens: Bool

    var body: some View {
        HStack(spacing: 5) {
            if let mark { mark.renderingMode(.template).resizable().scaledToFit().frame(width: 13, height: 13) }
            Text(text).lineLimit(1)
            if opens { Image(systemName: "arrow.up.right").font(.scaled(9, weight: .bold)).foregroundStyle(.tertiary) }
        }
        .font(.scaled(12, weight: .medium)).foregroundStyle(.secondary)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

/// One line that never wraps, centred and at most as wide as the feed: the connectors stretch up to that and shrink first when the window narrows.
struct PipelineStrip: View {
    let steps: [PipelineStep]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Capsule().fill(steps[index - 1].state == .done ? Color.green : Color.secondary.opacity(0.3))
                        .frame(minWidth: 8, maxWidth: .infinity).frame(height: 2)
                }
                PipelineStepView(index: index, step: step)
            }
        }
    }
}

struct PipelineStepView: View {
    let index: Int
    let step: PipelineStep

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if step.loops {
                    SpinningGlyph(symbol: "arrow.triangle.2.circlepath", diameter: 10)
                } else {
                    StateMark(text: mark, shape: step.state.shape, size: 10, weight: .bold).foregroundStyle(fill == nil ? Color.secondary : .white)
                }
            }
            .frame(width: 17, height: 17)
            .background(Circle().fill(fill ?? Color.secondary.opacity(0.15)))
            Text(step.name).font(.callout.weight(.medium))
                .foregroundStyle(step.state == .waiting || step.state == .done ? Color.secondary : .primary)
        }
        .lineLimit(1)
        .help([step.name, step.label].compactMap { $0 }.joined(separator: " "))
        // the circle is a glyph or a colour, never read: the state and the words are said instead, labels hidden or not
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.name)
        .accessibilityValue([spoken, step.label].compactMap { $0 }.joined(separator: ", "))
    }

    private var spoken: String {
        switch step.state {
        case .done: "done"
        case .current: "in progress"
        case .waiting: "not started"
        case .input: "needs your input"
        case .error: "failed"
        case .cancelled: "cancelled"
        }
    }

    private var mark: String {
        switch step.state {
        case .done: "✓"
        case .input, .error: "!"
        case .cancelled: "✕"
        case .current, .waiting: "\(index + 1)"
        }
    }

    private var fill: Color? {
        switch step.state {
        case .done: .green
        case .current: .themeAccent
        case .input: .orange
        case .error: .red
        case .waiting, .cancelled: nil
        }
    }
}

private extension EpicTab {
    var icon: String {
        switch self {
        case .agentOutput: "terminal"
        case .filesChanged: "doc.text"
        }
    }
}

/// The epic's links in one glass pill of the toolbar, the size of the others (Search and Filter, Pause and Stop): its pull request (when it
/// has one) and its issue. Each shows only when the engine gave a web link.
struct EpicLinks: View {
    let prURL: String?
    let issueURL: String?

    var body: some View {
        let pr = prURL.flatMap(browserURL), issue = issueURL.flatMap(browserURL)
        HStack(spacing: 0) {
            if let pr { ToolbarPillButton(title: "Open PR", mark: GitHubMark.image) { NSWorkspace.shared.open(pr) }.help("Open the pull request") }
            if let issue { ToolbarPillButton(title: "Open issue", icon: "number") { NSWorkspace.shared.open(issue) }.help("Open the issue") }
        }
        .glassEffect(.regular, in: .capsule)
    }
}
