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
    /// The `files` reply, once the window asks for it.
    var files: FilesReply?
    /// What a queued epic will do; nil for any other.
    var plan: QueuedPlan?
    /// The reason and the Resume button of a stopped epic, with the store that remembers a Resume in flight; nil for any other.
    var resume: (card: ResumeCard, store: EpicStore)?
    @State private var tab = EpicTab.agentOutput
    /// Whether the page is at its end: a session that starts scrolls it into view only then, so reading further up is not interrupted.
    @State private var atEnd = true

    var body: some View {
        ScrollViewReader { page in
            scroll
                // the sessions run oldest to newest: the page opens on the newest, and follows a new one while it sits at the end
                .defaultScrollAnchor(tab == .agentOutput ? .bottom : nil, for: .initialOffset)
                .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.containerSize.height >= $0.contentSize.height - 60 } action: { _, now in
                    atEnd = now
                }
                .onChange(of: sessions.sections.last?.id) {
                    if atEnd, tab == .agentOutput { withAnimation { page.scrollTo(SessionSectionsView.endID, anchor: .bottom) } }
                }
        }
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                EpicHeaderView(header: epicHeader(subject, reply: reply))
                if let resume { ResumeCardView(card: resume.card, store: resume.store, epic: EpicRef(repo: subject.repo, issue: subject.issue)) }
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
                .padding(.horizontal, 20).padding(.vertical, 10)
        }
    }

    // The tabs are empty states for now.
    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .agentOutput:
            if let empty = subject.outputEmptyState {
                EmptyStateView(state: empty).frame(minHeight: 260)
                if let plan { QueuedPlanView(plan: plan) }
            } else if sessions.loaded == false {
                LoadingStateView(title: "Loading activity", line: "Reading what the agents did on this epic.").frame(minHeight: 260)
            } else if sessions.sections.isEmpty {
                if let steps = startingSteps(subject, reply: reply) {
                    StartingView(steps: steps).frame(minHeight: 260)
                } else {
                    EmptyStateView(state: .noActivity).frame(minHeight: 260)
                }
            } else {
                SessionSectionsView(epic: EpicRef(repo: subject.repo, issue: subject.issue), list: sessions, folds: $folds)
            }
        case .filesChanged:
            FilesChangedView(files: files)
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
                        Text(label).font(.system(size: 12, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 2)
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
            case .needsYou: disc(.orange, "!")
            case .ready: disc(.blue, "✓")
            case .done: disc(.green, "✓")
            case .cancelled: disc(.gray, "✕")
            case .waiting: Circle().strokeBorder(Color.gray, lineWidth: 3).frame(width: 24, height: 24)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    private func disc(_ color: Color, _ mark: String) -> some View {
        Circle().fill(color).frame(width: 30, height: 30).overlay { Text(mark).font(.system(size: 15, weight: .heavy)).foregroundStyle(.white) }
    }
}

private struct StatePill: View {
    let state: EpicMenuState
    let text: String

    var body: some View {
        let color: Color = switch state {
        case .running: .green
        case .needsYou: .orange
        case .ready: .blue
        case .waiting, .cancelled: .gray
        case .done: .green
        }
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: 12, weight: .semibold)).foregroundStyle(color)
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
            if opens { Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary) }
        }
        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

/// One line that never wraps: the connectors stretch, and when the labels no longer fit they give way to the bare names.
struct PipelineStrip: View {
    let steps: [PipelineStep]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(labelled: true)
            line(labelled: false)
        }
    }

    private func line(labelled: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Capsule().fill(steps[index - 1].state == .done ? Color.green : Color.secondary.opacity(0.3))
                        .frame(minWidth: 8, maxWidth: .infinity).frame(height: 2)
                }
                PipelineStepView(index: index, step: step, labelled: labelled)
            }
        }
    }
}

struct PipelineStepView: View {
    let index: Int
    let step: PipelineStep
    let labelled: Bool

    var body: some View {
        HStack(spacing: 5) {
            Group {
                if step.loops {
                    SpinningGlyph(symbol: "arrow.triangle.2.circlepath", diameter: 10)
                } else {
                    Text(mark).font(.system(size: 10, weight: .bold)).foregroundStyle(fill == nil ? Color.secondary : .white)
                }
            }
            .frame(width: 17, height: 17)
            .background(Circle().fill(fill ?? Color.secondary.opacity(0.15)))
            Text(step.name).font(.callout.weight(.medium))
                .foregroundStyle(step.state == .waiting || step.state == .done ? Color.secondary : .primary)
            if labelled, let label = step.label { Text(label).font(.caption).foregroundStyle(.tertiary) }
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
        case .current: .accentColor
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

/// The epic's links in one toolbar pill, a divider between them: its pull request (when it has one) and its issue. Each shows
/// only when the engine gave a web link.
struct EpicLinks: View {
    let prURL: String?
    let issueURL: String?

    var body: some View {
        let pr = prURL.flatMap(browserURL), issue = issueURL.flatMap(browserURL)
        HStack(spacing: 0) {
            link("Open PR", url: pr) { GitHubMark.image.renderingMode(.template).resizable().scaledToFit().frame(width: 13, height: 13) }
            if pr != nil, issue != nil { Divider().frame(height: 14) }
            link("Open issue", url: issue) { Image(systemName: "number").font(.system(size: 12, weight: .medium)) }
        }
    }

    @ViewBuilder private func link(_ title: String, url: URL?, @ViewBuilder icon: () -> some View) -> some View {
        if let url {
            Button { NSWorkspace.shared.open(url) } label: {
                Label { Text(title) } icon: { icon() }.labelStyle(.titleAndIcon).padding(.horizontal, 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
