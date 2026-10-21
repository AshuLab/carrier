import AppKit
import CarrierCore
import SwiftUI

struct PanelView: View {
    let model: PanelModel

    private var snapshot: PanelSnapshot? {
        if case .running(let snapshot)? = model.state { return snapshot }
        return nil
    }

    /// The selected epic when it is in the snapshot.
    private var epic: (subject: EpicSubject, header: EpicHeader, now: Int)? {
        guard case .epic(let repo, let issue) = model.shell.selection, let snapshot,
            let subject = snapshot.subject(repo: repo, issue: issue)
        else { return nil }
        return (subject, epicHeader(subject), snapshot.now)
    }

    var body: some View {
        @Bindable var shell = model.shell
        let groupBy = Binding(get: { model.groupBy }, set: { model.groupBy = $0; SidebarStore().groupBy = $0 })
        let columns = Binding<NavigationSplitViewVisibility>(
            get: { shell.sidebarShown ? .all : .detailOnly }, set: { shell.sidebarShown = $0 != .detailOnly }
        )
        NavigationSplitView(columnVisibility: columns) {
            SidebarView(snapshot: snapshot, selection: $shell.selection, groupBy: groupBy)
        } detail: {
            Group {
                if let epic {
                    EpicView(subject: epic.subject, reply: nil, filesChanged: 0, now: epic.now)
                        .id("\(epic.subject.repo)#\(epic.subject.issue)")
                } else {
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
                                Running(snapshot: snapshot, selection: shell.selection)
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .navigationTitle(epic.map { "\($0.subject.repo.split(separator: "/").last ?? "") #\($0.subject.issue)" } ?? "Carrier")
            .inspector(isPresented: $shell.inspectorShown) {
                Text("Inspector").foregroundStyle(.secondary)
                    .inspectorColumnWidth(min: 280, ideal: 316, max: 400)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { shell.toggleSidebar() } label: { Label("Sidebar", systemImage: "sidebar.leading") }
                    .help("Show or hide the sidebar")
            }
            if let epic {
                ToolbarItemGroup(placement: .primaryAction) {
                    OpenLinkButton(title: "Open PR", url: epic.header.prURL)
                    OpenLinkButton(title: "Open issue", url: epic.header.issueURL)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { shell.toggleInspector() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                    .help("Show or hide the inspector")
            }
        }
        .frame(minWidth: 980, minHeight: 600)
    }
}

private struct Running: View {
    let snapshot: PanelSnapshot
    let selection: Selection

    var body: some View {
        switch selection {
        case .overview:
            Overview(snapshot: snapshot)
        case .epic(let repo, let issue):
            // not in the snapshot (any more)
            Text("\(repo) #\(issue)")
        case .settings:
            Text("Settings").foregroundStyle(.secondary)
        case .about:
            Text("About Carrier").foregroundStyle(.secondary)
        }
    }
}

private struct Overview: View {
    let snapshot: PanelSnapshot

    var body: some View {
        let needsYou = snapshot.epics.filter { $0.status == .needsHuman }
        let running = snapshot.epics.filter { $0.status == .running }
        CarrierBoxView(snapshot: snapshot)
        if needsYou.isEmpty == false {
            PanelSection(title: "Needs you") { ForEach(needsYou, id: \.key) { EpicCard(epic: $0, now: snapshot.now) } }
        }
        if running.isEmpty == false {
            PanelSection(title: "Running") { ForEach(running, id: \.key) { EpicCard(epic: $0, now: snapshot.now) } }
        }
        if snapshot.queue.isEmpty == false {
            PanelSection(title: "Queue \(snapshot.queue.count)") {
                ForEach(snapshot.queue, id: \.key) { Text("\($0.repo) #\($0.issue)") }
            }
        }
        if snapshot.done.isEmpty == false {
            PanelSection(title: "Ready for test") {
                ForEach(snapshot.done, id: \.key) { DoneRow(done: $0, now: snapshot.now) }
            }
        }
        if snapshot.epics.isEmpty && snapshot.queue.isEmpty && snapshot.done.isEmpty {
            Text("Idle. Mark an epic solve:epic:ready in a watched repo to start one.").foregroundStyle(.secondary)
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
