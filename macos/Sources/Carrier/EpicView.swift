import AppKit
import CarrierCore
import SwiftUI

/// An epic's centre: the pipeline fixed on top as a safe-area bar (the content scrolls under it, blurred), then the header
/// and the two tabs. `reply`, `filesChanged` and `sessions` are empty until the window gets them from the engine.
struct EpicView: View {
    let subject: EpicSubject
    let reply: EpicReply?
    let filesChanged: Int
    let now: Int
    let sessions: SessionList
    @Binding var folds: SessionFolds
    /// The `files` reply, once the window asks for it.
    var files: FilesReply?
    /// What a queued epic will do; nil for any other.
    var plan: QueuedPlan?
    @State private var tab = EpicTab.agentOutput

    var body: some View {
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
            PipelineStrip(steps: pipelineSteps(subject, reply: reply, now: now))
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
            } else if sessions.sections.isEmpty {
                Text("The agents' output appears here.").foregroundStyle(.secondary).padding(.vertical, 40)
            } else {
                SessionSectionsView(list: sessions, folds: $folds)
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
                    Chip(text: header.repo, symbol: "arrow.triangle.branch")
                    if let url = browserURL(header.issueURL) {
                        Button { NSWorkspace.shared.open(url) } label: {
                            Chip(text: "#\(header.issue)", symbol: "smallcircle.filled.circle")
                        }
                        .buttonStyle(.plain).help("Open the issue")
                    }
                    ForEach(header.labels, id: \.self) { label in
                        Text(label).font(.caption.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 1)
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
        case .waiting: .gray
        }
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold)).foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.2)))
    }
}

private struct Chip: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 2)
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
            Text(mark).font(.system(size: 10, weight: .bold)).foregroundStyle(fill == nil ? Color.secondary : .white)
                .frame(width: 17, height: 17)
                .background(Circle().fill(fill ?? Color.secondary.opacity(0.15)))
            Text(step.name).font(.callout.weight(.medium))
                .foregroundStyle(step.state == .current || step.state == .problem ? Color.primary : .secondary)
            if labelled, let label = step.label { Text(label).font(.caption).foregroundStyle(.tertiary) }
        }
        .lineLimit(1)
        .help([step.name, step.label].compactMap { $0 }.joined(separator: " "))
    }

    private var mark: String {
        switch step.state {
        case .done: "✓"
        case .problem: "!"
        case .current, .waiting: "\(index + 1)"
        }
    }

    private var fill: Color? {
        switch step.state {
        case .done: .green
        case .current: .accentColor
        case .problem: .orange
        case .waiting: nil
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
            link("Open PR", icon: "arrow.triangle.pull", url: pr)
            if pr != nil, issue != nil { Divider().frame(height: 14) }
            link("Open issue", icon: "smallcircle.filled.circle", url: issue)
        }
    }

    @ViewBuilder private func link(_ title: String, icon: String, url: URL?) -> some View {
        if let url {
            Button { NSWorkspace.shared.open(url) } label: {
                Label(title, systemImage: icon).labelStyle(.titleAndIcon).padding(.horizontal, 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
