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

    private func queuedPlan(_ subject: EpicSubject) -> QueuedPlan? {
        guard case .queued(let queued, let position) = subject else { return nil }
        return snapshot?.queuedPlan(for: queued, position: position)
    }

    /// What the engine is asked for: the selected epic's data, nothing with no epic selected.
    private var focus: EpicFocus? {
        guard let epic else { return nil }
        let ref = EpicRef(repo: epic.subject.repo, issue: epic.subject.issue)
        var running = false
        if case .active(let active) = epic.subject { running = active.status == .running }
        return epicFocus(ref, running: running, data: model.epics.data[ref], folds: model.epics.folds)
    }

    /// The toolbar's title and the line under it, as in the mockup: each screen says what it is.
    private var title: String {
        if let epic { return "\(epic.subject.repo.split(separator: "/").last ?? "") #\(epic.subject.issue)" }
        switch model.shell.selection {
        case .overview where snapshot != nil: return "Overview"
        case .settings: return "Settings"
        default: return "Carrier"
        }
    }

    private var subtitle: String {
        switch model.shell.selection {
        case .overview: snapshot.map { overviewSubtitle($0, repos: $0.watched?.count ?? $0.repos) } ?? ""
        case .settings: "what the app starts Carrier with"
        case .epic: ""
        }
    }

    var body: some View {
        @Bindable var shell = model.shell
        @Bindable var epics = model.epics
        let groupBy = Binding(get: { model.groupBy }, set: { model.groupBy = $0; SidebarStore().groupBy = $0 })
        let columns = Binding<NavigationSplitViewVisibility>(
            get: { shell.sidebarShown ? .all : .detailOnly }, set: { shell.sidebarShown = $0 != .detailOnly }
        )
        NavigationSplitView(columnVisibility: columns) {
            SidebarView(snapshot: snapshot, selection: $shell.selection, groupBy: groupBy, onAbout: shell.showAbout)
        } detail: {
            // the right panel is ours, not `.inspector`: that one, inside a NavigationSplitView, loops AppKit's layout while the window
            // resizes and the app dies with "more Update Constraints passes than there are views"
            HStack(spacing: 0) {
                Group {
                    if let epic {
                        let data = model.epics.data[EpicRef(repo: epic.subject.repo, issue: epic.subject.issue)]
                        EpicView(
                            subject: epic.subject, reply: data?.epic, filesChanged: filesChangedCount(data?.files), now: epic.now,
                            sessions: sessionList(data?.sessions, transcripts: data?.transcripts ?? [:]), folds: $epics.folds, files: data?.files,
                            plan: queuedPlan(epic.subject)
                        )
                            .id("\(epic.subject.repo)#\(epic.subject.issue)")
                    } else if shell.selection == .settings {
                        // reachable whatever Carrier is doing: it is where a stopped Carrier is made ready
                        SettingsScreen()
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 26) {
                                switch model.state {
                                case nil:
                                    Text("Connecting…").foregroundStyle(.secondary)
                                case .stopped?, .incompatible?:
                                    // Carrier is not answering: nothing else to show
                                    Label(model.state?.menuLine ?? "", systemImage: "stop.circle").font(.title3)
                                    if model.state == .stopped { StartCarrierButton() }
                                case .running(let snapshot)?:
                                    Running(snapshot: snapshot, selection: $shell.selection)
                                }
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                }
                // only an epic has something to inspect; Overview and Settings are a single column
                if let epic, shell.inspectorShown {
                    Divider()
                    InspectorTabsView(subject: epic.subject, reply: model.epics.data[EpicRef(repo: epic.subject.repo, issue: epic.subject.issue)]?.epic)
                        .frame(width: 316)
                        .background(.background.secondary)
                        .transition(.move(edge: .trailing))
                }
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { withAnimation(.smooth(duration: 0.25)) { shell.toggleSidebar() } } label: { Label("Sidebar", systemImage: "sidebar.leading") }
                    .help("Show or hide the sidebar")
            }
            if let snapshot, shell.selection == .overview {
                // two pills: the check against GitHub, then what governs Carrier itself (intake and stopping)
                ToolbarItem(placement: .primaryAction) {
                    Button { MenuControls.shared.checkNow() } label: { Label("Check now", systemImage: "arrow.clockwise") }
                        .help("Check GitHub now")
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { MenuControls.shared.pauseOrResume() } label: {
                        Label(snapshot.paused ? "Resume" : "Pause", systemImage: snapshot.paused ? "play.fill" : "pause.fill")
                    }
                    .help(snapshot.paused ? "Resume intake" : "Pause intake")
                    Button { MenuControls.shared.stopCarrier() } label: {
                        Label { Text("Stop") } icon: { Image(systemName: "stop.fill").foregroundStyle(.red) }
                    }
                    .help("Stop Carrier")
                }
            }
            if let epic {
                ToolbarItemGroup(placement: .primaryAction) {
                    OpenLinkButton(title: "Open PR", url: epic.header.prURL)
                    OpenLinkButton(title: "Open issue", url: epic.header.issueURL)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { withAnimation(.smooth(duration: 0.25)) { shell.toggleInspector() } } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                        .help("Show or hide the inspector")
                }
            }
        }
        .overlay {
            if shell.aboutShown {
                AboutSheetView(state: model.state, onInput: shell.aboutInput)
            }
        }
        .frame(minWidth: 980, minHeight: 600)
        .onChange(of: focus, initial: true) { model.epics.poller.show(focus) }
    }
}

private struct Running: View {
    let snapshot: PanelSnapshot
    @Binding var selection: Selection

    var body: some View {
        switch selection {
        case .overview:
            Overview(snapshot: snapshot, selection: $selection)
        case .epic(let repo, let issue):
            // not in the snapshot (any more)
            Text("\(repo) #\(issue)")
        case .settings:
            EmptyView()  // PanelView shows SettingsScreen
        }
    }
}

private struct Overview: View {
    let snapshot: PanelSnapshot
    @Binding var selection: Selection

    var body: some View {
        YourTurnView(snapshot: snapshot, selection: $selection)
        RunningView(snapshot: snapshot, selection: $selection)
        if snapshot.queue.isEmpty == false {
            VStack(alignment: .leading, spacing: 8) {
                OverviewTitle(title: "Up next", detail: "\(snapshot.queue.count)")
                OverviewCard {
                    ForEach(snapshot.queue, id: \.key) { Text("\($0.repo) #\($0.issue)").padding(.vertical, 8) }
                }
            }
        }
        CarrierBoxView(snapshot: snapshot)
    }
}

private extension PanelEpic { var key: String { "\(repo)#\(issue)" } }
private extension PanelSnapshot.QueuedEpic { var key: String { "\(repo)#\(issue)" } }
