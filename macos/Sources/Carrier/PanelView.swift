import AppKit
import CarrierCore
import SwiftUI

struct PanelView: View {
    let model: PanelModel
    /// The last Check now pressed from the toolbar, for the button to say it is checking.
    @State private var checkAsked: CheckAsked?
    /// The right panel's width: also the empty toolbar item that keeps the epic's buttons off it.
    private static let inspectorWidth: CGFloat = 316

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

    private func resumeCard(_ subject: EpicSubject) -> ResumeCard? {
        guard case .active(let active) = subject else { return nil }
        return CarrierCore.resumeCard(active, canResume: model.epics.canResume)
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
        let collapse = Binding(get: { model.collapse }, set: { model.collapse = $0 })
        let columns = Binding<NavigationSplitViewVisibility>(
            get: { shell.sidebarShown ? .all : .detailOnly }, set: { shell.sidebarShown = $0 != .detailOnly }
        )
        NavigationSplitView(columnVisibility: columns) {
            SidebarView(snapshot: snapshot, state: model.state, selection: $shell.selection, groupBy: groupBy, collapse: collapse, onAbout: shell.showAbout)
        } detail: {
            // the right panel is ours, not `.inspector`: that one, inside a NavigationSplitView, loops AppKit's layout while the window
            // resizes and the app dies with "more Update Constraints passes than there are views"
            HStack(spacing: 0) {
                Group {
                    if let epic {
                        let data = model.epics.data[EpicRef(repo: epic.subject.repo, issue: epic.subject.issue)]
                        let over: Bool = if case .ended = epic.subject { true } else { false }
                        EpicView(
                            subject: epic.subject, reply: data?.epic, filesChanged: filesChangedCount(data?.files),
                            sessions: sessionList(data?.sessions, transcripts: data?.transcripts ?? [:], slices: data?.epic?.slices ?? [], now: epic.now, resumable: over == false), folds: $epics.folds, files: data?.files,
                            plan: queuedPlan(epic.subject), resume: resumeCard(epic.subject)
                        )
                            .id("\(epic.subject.repo)#\(epic.subject.issue)")
                    } else if shell.selection == .settings {
                        // reachable whatever Carrier is doing: it is where a stopped Carrier is made ready
                        SettingsScreen(state: model.state)
                    } else if case .running(let snapshot)? = model.state {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 26) {
                                Running(snapshot: snapshot, selection: $shell.selection)
                            }
                            .padding(18)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    } else {
                        // Carrier is not answering (or has not yet): what to do about it
                        StoppedView(state: model.state, selection: $shell.selection)
                    }
                }
                // only an epic has something to inspect; Overview and Settings are a single column. The panel runs up behind the
                // title bar, like the sidebar on the other side. It stays in the tree and the width of its slot goes between 0 and its own,
                // the panel anchored to the slot's left edge so it leaves through the window's right one; a view that came and went with
                // a transition would not move like the sidebar does
                if let epic {
                    let data = model.epics.data[EpicRef(repo: epic.subject.repo, issue: epic.subject.issue)]
                    HStack(spacing: 0) {
                        Divider().ignoresSafeArea(.container, edges: .top)
                        InspectorTabsView(subject: epic.subject, reply: data?.epic, sessions: data?.sessions)
                            .frame(width: Self.inspectorWidth)
                            .background(.background.secondary, ignoresSafeAreaEdges: .all)
                    }
                    .frame(width: shell.inspectorShown ? Self.inspectorWidth + 1 : 0, alignment: .leading)
                    .allowsHitTesting(shell.inspectorShown)
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
            if let epic {
                ToolbarItem(placement: .primaryAction) { EpicLinks(prURL: epic.header.prURL, issueURL: epic.header.issueURL) }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    Button { withAnimation(.smooth(duration: 0.25)) { shell.toggleInspector() } } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                        .help("Show or hide the inspector")
                }
                if shell.inspectorShown {
                    // The toolbar is the window's, so its right end is over the panel, which runs up behind the title bar. An empty item
                    // as wide as the panel at that end keeps the buttons on the centre's side of it.
                    ToolbarItem(placement: .primaryAction) { Color.clear.frame(width: Self.inspectorWidth, height: 1) }
                        .sharedBackgroundVisibility(.hidden)
                }
            }
            if let snapshot, shell.selection == .overview {
                // two pills: the check against GitHub, then what governs Carrier itself (intake and stopping)
                ToolbarItem(placement: .primaryAction) {
                    // the engine polls on its own after the answer: the button says so until the next check is scheduled again
                    let checking = isChecking(snapshot, asked: checkAsked, now: Date())
                    Button {
                        checkAsked = CheckAsked(at: Date(), nextCheckAt: snapshot.nextCheckAt)
                        MenuControls.shared.checkNow()
                    } label: {
                        Label(checking ? "Checking…" : "Check now", systemImage: "arrow.clockwise")
                            .symbolEffect(.rotate, options: .repeating, isActive: checking)
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(checking)
                    .help(checking ? "Checking GitHub…" : "Check GitHub now")
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { MenuControls.shared.pauseOrResume() } label: {
                        Label(snapshot.paused ? "Resume" : "Pause", systemImage: snapshot.paused ? "play.fill" : "pause.fill").labelStyle(.titleAndIcon)
                    }
                    .help(snapshot.paused ? "Resume intake" : "Pause intake")
                    Button { MenuControls.shared.stopCarrier() } label: {
                        Label { Text("Stop") } icon: { Image(systemName: "stop.fill").foregroundStyle(.red) }.labelStyle(.titleAndIcon)
                    }
                    .help("Stop Carrier")
                }
            }
        }
        .overlay {
            if shell.aboutShown {
                AboutSheetView(state: model.state, onInput: shell.aboutInput)
            }
        }
        .frame(minWidth: 1100, minHeight: 600)
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
        if snapshot.queue.isEmpty == false { UpNextView(snapshot: snapshot, selection: $selection) }
        WatchedReposView(snapshot: snapshot)
    }
}

private extension PanelEpic { var key: String { "\(repo)#\(issue)" } }
private extension PanelSnapshot.QueuedEpic { var key: String { "\(repo)#\(issue)" } }
