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
    @State private var tab = EpicTab.agentOutput

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                EpicHeaderView(header: epicHeader(subject, reply: reply))
                Picker("", selection: $tab) {
                    ForEach(EpicTab.allCases, id: \.self) { Text($0.title(filesChanged: max(filesChanged, filesChangedCount(files)))).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(maxWidth: 320)
                tabContent
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
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
            if case .queued = subject {
                EmptyStateView(state: .waitingForSlot).frame(minHeight: 260)
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

private struct EpicHeaderView: View {
    let header: EpicHeader

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(header.title).font(.title2.weight(.bold)).lineLimit(2)
            HStack(spacing: 8) {
                Text(header.subtitle).foregroundStyle(.secondary)
                ForEach(header.labels, id: \.self) { label in
                    Text(label).font(.caption.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }
                if let label = header.prLabel ?? (header.prURL == nil ? nil : "PR"), let url = header.prURL.flatMap(browserURL) {
                    Link("\(label) ↗", destination: url)
                }
            }
            .font(.callout).lineLimit(1)
        }
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

/// Opens a link from the engine in the default browser; shown only when there is one and it is a web link.
struct OpenLinkButton: View {
    let title: String
    let url: String?

    var body: some View {
        if let target = url.flatMap(browserURL) {
            Button(title) { NSWorkspace.shared.open(target) }
        }
    }
}
