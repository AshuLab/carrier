import AppKit
import CarrierCore
import SwiftUI

/// What the sidebar lists: the overview, then one item per section of the panel.
private enum SidebarItem: String, CaseIterable, Identifiable {
    case overview, needsYou, running, queue, ready

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .needsYou: "Needs you"
        case .running: "Running"
        case .queue: "Queue"
        case .ready: "Ready for test"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .needsYou: "exclamationmark.bubble"
        case .running: "play.circle"
        case .queue: "tray.full"
        case .ready: "checkmark.circle"
        }
    }

    init(_ state: EpicMenuState) {
        switch state {
        case .needsYou: self = .needsYou
        case .running: self = .running
        case .waiting: self = .queue
        case .ready: self = .ready
        }
    }

    /// How many entries the section holds; the overview has no count.
    func count(in snapshot: PanelSnapshot) -> Int {
        switch self {
        case .overview: 0
        case .needsYou: snapshot.epics.filter { $0.status == .needsHuman }.count
        case .running: snapshot.epics.filter { $0.status == .running }.count
        case .queue: snapshot.queue.count
        case .ready: snapshot.done.count
        }
    }
}

struct PanelView: View {
    let model: PanelModel
    @State private var selection: SidebarItem? = .overview

    private var snapshot: PanelSnapshot? {
        if case .running(let snapshot)? = model.state { return snapshot }
        return nil
    }

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.title, systemImage: item.symbol).badge(snapshot.map(item.count) ?? 0)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
            .safeAreaInset(edge: .bottom) {
                Text(model.state?.menuLine ?? "Connecting…")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch model.state {
                    case nil:
                        Text("Connecting…").foregroundStyle(.secondary)
                    case .stopped?, .incompatible?:
                        // Carrier is not answering: nothing else to show
                        Label(model.state?.menuLine ?? "", systemImage: "stop.circle").font(.title3)
                        if model.state == .stopped { StartCarrierButton() }
                    case .running(let snapshot)?:
                        Running(snapshot: snapshot, item: selection ?? .overview)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle((selection ?? .overview).title)
        }
        .frame(minWidth: 760, minHeight: 420)
        // an epic chosen in the menu; the sidebar lists sections, not epics, so it selects the section the epic is in
        .onChange(of: model.selected) { _, epic in
            if let epic { selection = SidebarItem(epic.state) }
        }
    }
}

private struct Running: View {
    let snapshot: PanelSnapshot
    let item: SidebarItem

    /// The overview shows every section; any other item shows only its own.
    private func shows(_ section: SidebarItem) -> Bool { item == .overview || item == section }

    var body: some View {
        let needsYou = snapshot.epics.filter { $0.status == .needsHuman }
        let running = snapshot.epics.filter { $0.status == .running }
        Header(snapshot: snapshot)
        if shows(.needsYou) && needsYou.isEmpty == false {
            PanelSection(title: "Needs you") { ForEach(needsYou, id: \.key) { EpicCard(epic: $0, now: snapshot.now) } }
        }
        if shows(.running) && running.isEmpty == false {
            PanelSection(title: "Running") { ForEach(running, id: \.key) { EpicCard(epic: $0, now: snapshot.now) } }
        }
        if shows(.queue) && snapshot.queue.isEmpty == false {
            PanelSection(title: "Queue \(snapshot.queue.count)") {
                ForEach(snapshot.queue, id: \.key) { Text("\($0.repo) #\($0.issue)") }
            }
        }
        if shows(.ready) && snapshot.done.isEmpty == false {
            PanelSection(title: "Ready for test") {
                ForEach(snapshot.done, id: \.key) { DoneRow(done: $0, now: snapshot.now) }
            }
        }
        if item == .overview && snapshot.epics.isEmpty && snapshot.queue.isEmpty && snapshot.done.isEmpty {
            Text("Idle. Mark an epic solve:epic:ready in a watched repo to start one.").foregroundStyle(.secondary)
        } else if item != .overview && item.count(in: snapshot) == 0 {
            Text("Nothing in \(item.title.lowercased()).").foregroundStyle(.secondary)
        }
    }
}

private struct Header: View {
    let snapshot: PanelSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Carrier running", systemImage: "play.circle.fill").foregroundStyle(.green).font(.title3)
                Text(uptimeLine(snapshot)).foregroundStyle(.secondary)
                Spacer()
                Chip(text: "slots \(snapshot.slots.busy)/\(snapshot.slots.total)")
            }
            Text("\(reposLine(snapshot.repos)) · \(nextCheckLine(snapshot))").font(.callout).foregroundStyle(.secondary)
            if snapshot.paused {
                Label("Intake is paused: new epics wait in the queue", systemImage: "pause.circle").foregroundStyle(.orange)
            }
            if let problem = snapshot.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }
}

private struct EpicCard: View {
    let epic: PanelEpic
    let now: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(epic.repo) #\(epic.issue)").font(.headline)
                Spacer()
                if epic.status == .running {
                    Button("Output") { if let id = epic.executionId { AgentOutputWindow.show(title: "\(epic.repo) #\(epic.issue)", executionId: id) } }
                        .buttonStyle(.glass).controlSize(.small).disabled(epic.executionId == nil)
                }
                OpenButton(title: "Open PR", url: epic.prUrl)
                OpenButton(title: "Open issue", url: epic.issueUrl)
            }
            if let reason = epic.needsHumanReason { Text(reason).foregroundStyle(.orange) }
            HStack(spacing: 6) {
                if epic.stage == nil { Text("starting").font(.caption).foregroundStyle(.secondary) }
                ForEach(stageChain(epic.stage), id: \.name) { Chip(text: $0.name, on: $0.current) }
                if let round = roundLine(epic) { Text(round).font(.caption).foregroundStyle(.secondary) }
                Chip(text: blockersLine(epic.blockers), on: epic.blockers > 0, color: .red)
            }
            Text("\(stageTimeLine(epic, now: now)) · \(activityLine(epic, now: now))").font(.caption).foregroundStyle(.secondary)
            if let slices = epic.slices, let line = slicesLine(slices) {
                HStack(spacing: 8) {
                    ProgressView(value: Double(slices.done), total: Double(slices.total)).frame(maxWidth: 220)
                    Text(line).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if let error = epic.lastError { Text("error: \(error)").font(.caption).foregroundStyle(.red) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
    }
}

private struct DoneRow: View {
    let done: PanelSnapshot.DoneEpic
    let now: Int

    var body: some View {
        HStack {
            Text("\(done.repo) #\(done.issue)")
            Text(agoLine(done.finishedAt, now: now)).font(.caption).foregroundStyle(.secondary)
            Spacer()
            OpenButton(title: "Open PR", url: donePullURL(done))
            OpenButton(title: "Open issue", url: doneIssueURL(done))
        }
    }
}

/// Opens a link from the engine in the default browser; absent when there is no link or it is not a web link.
private struct OpenButton: View {
    let title: String
    let url: String?

    var body: some View {
        if let target = url.flatMap(browserURL) {
            Button(title) { NSWorkspace.shared.open(target) }.buttonStyle(.glass).controlSize(.small)
        }
    }
}

private struct Chip: View {
    let text: String
    var on = false
    var color: Color = .accentColor

    var body: some View {
        Text(text).font(.caption.weight(.medium)).padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(on ? color : Color.secondary.opacity(0.15)))
            .foregroundStyle(on ? Color.white : Color.secondary)
    }
}

private struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
    }
}

private extension PanelEpic { var key: String { "\(repo)#\(issue)" } }
private extension PanelSnapshot.QueuedEpic { var key: String { "\(repo)#\(issue)" } }
private extension PanelSnapshot.DoneEpic { var key: String { "\(repo)#\(issue)" } }
