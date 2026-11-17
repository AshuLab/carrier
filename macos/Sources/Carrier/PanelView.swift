import AppKit
import CarrierCore
import SwiftUI

struct PanelView: View {
    private let timeChanges = TimeFormatChanges()
    let model: PanelModel
    // the sidebar's preferences are read from the defaults, so the sidebar's menus and the Sidebar page of Settings change one value
    @AppStorage(SidebarStore.groupByKey) private var groupBy = GroupBy.status
    @AppStorage(SidebarStore.sessionSortKey) private var sessionSort = SessionSort.workspace
    @AppStorage(SidebarStore.archiveSortKey) private var archiveSort = ArchiveSort.dateArchived
    @AppStorage(AppPreferences.terminalDrawerHeightKey) private var terminalDrawerHeight: Double = AppPreferences.defaultTerminalDrawerHeight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let terminalStore = CarrierTerminalStore.shared
    /// The last Check now pressed from the toolbar, for the button to say it is checking.
    @State private var checkAsked: CheckAsked?
    /// The window's size, for the sheets over it.
    @State private var windowSize = CGSize(width: 1100, height: 700)
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
        var focus = epicFocus(ref, running: running, data: model.epics.data[ref], folds: model.epics.folds)
        focus.openFiles = model.epics.filesTabShown ? model.epics.openFiles[ref] ?? [] : []
        return focus
    }

    /// The toolbar's title and the line under it, as in the mockup: each screen says what it is.
    private var title: String {
        if let epic { return "\(epic.subject.repo.split(separator: "/").last ?? "") #\(epic.subject.issue)" }
        switch model.shell.selection {
        case .sessions: return "Sessions"
        case .session: return openSession.map(conversationTitle) ?? "Session"
        case .newSession: return "New session"
        case .terminals: return "Terminal"
        case .terminal(let id): return terminalStore.standaloneTerminal(id: id)?.title ?? "Terminal"
        case .archive: return "Archive"
        case .usage: return "Usage"
        default: return "Carrier"
        }
    }

    /// The row of the session whose conversation is open.
    private var openSession: SessionRow? {
        guard case .session(let id) = model.shell.selection else { return nil }
        return model.sessions.rows.first { $0.id == id }
    }

    private var subtitle: String {
        switch model.shell.selection {
        case .carrier: snapshot.map { overviewSubtitle($0, repos: $0.watched?.count ?? $0.repos) } ?? ""
        case .sessions: sessionsPage(model.sessions.rows, by: sessionSort).subtitle
        case .session: openSession.map(conversationSubtitle) ?? ""
        case .terminals: terminalsSubtitle(count: terminalStore.standaloneTerminals().count)
        case .terminal(let id): terminalStore.standaloneTerminal(id: id)?.subtitle() ?? ""
        case .archive: archivePage(model.sessions.rows, by: archiveSort, query: "").subtitle
        case .usage: "Limits left and what was used, per account"
        default: ""
        }
    }

    /// The pages that are an empty state for now; Home does not depend on the engine.
    private var emptyPage: EmptyState? {
        switch model.shell.selection {
        case .home: .welcome
        default: nil
        }
    }

    private var engineRunning: Bool {
        if case .running? = model.state { return true }
        return false
    }

    private func createNewTerminal() {
        let terminalId = terminalStore.createStandaloneTerminal(workingDirectory: NSHomeDirectory())
        model.shell.selection = .terminal(id: terminalId)
    }

    private func closeStandaloneTerminal(_ id: UUID) {
        Task {
            guard await terminalStore.closeAll(for: .terminal(id)) else { return }
            reconcileSelectedTerminal()
        }
    }

    private func reconcileSelectedTerminal() {
        guard case .terminal(let currentId) = model.shell.selection else { return }
        guard terminalStore.standaloneTerminal(id: currentId) == nil else { return }
        if let nextId = terminalStore.standaloneTerminals().first?.id {
            model.shell.selection = .terminal(id: nextId)
        } else {
            model.shell.selection = .terminals
        }
    }

    private func setDrawerOpen(_ open: Bool, for owner: TerminalOwner) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            model.shell.setTerminalDrawerOpen(open, for: owner)
        }
    }

    private func toggleSessionTerminal(for session: SessionRow) {
        let owner = TerminalOwner.session(session.id)
        if model.shell.isTerminalDrawerOpen(for: owner) == false,
           terminalStore.tabs(for: owner).isEmpty {
            _ = terminalStore.openTab(for: owner, workingDirectory: session.folder)
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            model.shell.toggleTerminalDrawer(for: owner)
        }
    }

    /// Launches or focuses a validated epic Continue-in-Terminal session inside the epic's integrated bottom drawer.
    private func continueEpicInTerminal(epic: EpicRef, section: SessionSection, resume: ValidResume) {
        let launch = embeddedResumeLaunch(resume)
        guard isAccessibleTerminalDirectory(launch.workingDirectory) else {
            NSLog("Carrier: continue in terminal refused because folder is inaccessible: %@", launch.workingDirectory)
            tell("The session folder is no longer accessible.")
            return
        }
        let owner = TerminalOwner.epic(repo: epic.repo, issue: epic.issue)
        if let existingTab = terminalStore.tabs(for: owner).first(where: { tab in
            tab.orderedPanes.contains { $0.command == launch.command }
        }) {
            terminalStore.selectTab(existingTab.id, for: owner)
            setDrawerOpen(true, for: owner)
            if let matchingPaneId = existingTab.orderedPanes.first(where: { $0.command == launch.command })?.id {
                terminalStore.selectPane(matchingPaneId)
                terminalStore.focus(paneId: matchingPaneId)
            }
            return
        }
        let tab = terminalStore.openTab(
            for: owner,
            workingDirectory: launch.workingDirectory,
            command: launch.command,
            title: "\(section.agent) · \(section.role)",
            activate: true
        )
        setDrawerOpen(true, for: owner)
        terminalStore.focus(paneId: tab.activePaneId)
    }

    /// Bottom terminal drawer target for the currently selected chat session or epic, if any.
    private var activeDrawerTarget: (owner: TerminalOwner, defaultDirectory: String, isSessionDrawer: Bool)? {
        if case .session(let id) = model.shell.selection, let session = openSession {
            return (.session(id), session.folder, true)
        }
        if let epic {
            let owner = TerminalOwner.epic(repo: epic.subject.repo, issue: epic.subject.issue)
            let directory = terminalStore.activeTab(for: owner)?.workingDirectory ?? NSHomeDirectory()
            return (owner, directory, false)
        }
        return nil
    }

    var body: some View {
        @Bindable var shell = model.shell
        @Bindable var epics = model.epics
        let collapse = Binding(get: { model.collapse }, set: { model.collapse = $0 })
        let columns = Binding<NavigationSplitViewVisibility>(
            get: { shell.sidebarShown ? .all : .detailOnly }, set: { shell.sidebarShown = $0 != .detailOnly }
        )
        NavigationSplitView(columnVisibility: columns) {
            SidebarView(snapshot: snapshot, state: model.state, sessions: model.sessions, terminalStore: terminalStore, selection: $shell.selection, open: $shell.open, groupBy: $groupBy, sessionSort: $sessionSort, collapse: collapse, searchRequest: shell.searchRequest, chooseArchived: shell.chooseArchived, openSettings: { shell.showSettings() }, newSessionIn: { path in
                model.newSession.start(in: path)
                shell.selection = .newSession
            }, newTerminal: createNewTerminal, closeTerminal: closeStandaloneTerminal)
                .onChange(of: shell.open) { SidebarStore().open = shell.open }
                // leaving a session takes what it did as seen; opening one is seen at once, not at the next poll
                .onChange(of: shell.selection) { old, _ in
                    if case .session(let id) = old { model.leave(id) } else { model.refreshUnread() }
                }
                // the menu or the + while the draft is open: it starts blank again
                .onChange(of: shell.newSessionOpened) { model.newSession.blank() }
                .onChange(of: terminalStore.standaloneTerminals().map(\.id)) { reconcileSelectedTerminal() }
                .toolbar { UpdatePill.item }
        } detail: {
            // the right panel is ours, not `.inspector`: that one, inside a NavigationSplitView, loops AppKit's layout while the window
            // resizes and the app dies with "more Update Constraints passes than there are views"
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Group {
                        if let epic {
                            let ref = EpicRef(repo: epic.subject.repo, issue: epic.subject.issue)
                            let data = model.epics.data[ref]
                            let over: Bool = if case .ended = epic.subject { true } else { false }
                            EpicView(
                                subject: epic.subject, reply: data?.epic, filesChanged: filesChangedCount(data?.files),
                                sessions: sessionList(data?.sessions, transcripts: data?.transcripts ?? [:], slices: data?.epic?.slices ?? [], now: epic.now, resumable: over == false, folds: epics.folds), folds: $epics.folds, files: data?.files,
                                plan: queuedPlan(epic.subject), resume: resumeCard(epic.subject).map { ($0, model.epics) },
                                fileDiffs: epics.canOpenFiles ? FileDiffs(open: Binding(get: { epics.openFiles[ref] ?? [] }, set: { epics.openFiles[ref] = $0 }), shown: $epics.filesTabShown, fragments: data?.fragments ?? [:]) : nil,
                                onContinueInTerminal: { section, resume in
                                    continueEpicInTerminal(epic: ref, section: section, resume: resume)
                                }
                            )
                                .id("\(epic.subject.repo)#\(epic.subject.issue)")
                        } else if shell.selection == .sessions {
                            SessionsHomeView(sessions: model.sessions, sort: $sessionSort, newSession: { shell.selection = .newSession }) { shell.selection = .session(id: $0) }
                        } else if shell.selection == .terminals {
                            TerminalsHomeView(
                                store: terminalStore,
                                newTerminal: createNewTerminal,
                                select: { shell.selection = .terminal(id: $0) },
                                closeTerminal: closeStandaloneTerminal
                            )
                        } else if case .terminal(let id) = shell.selection {
                            TerminalDetailView(
                                store: terminalStore,
                                terminalId: id,
                                newTerminal: createNewTerminal
                            )
                            .id(id)
                        } else if shell.selection == .archive {
                            ArchiveView(rows: model.sessions.rows, sort: $archiveSort) { shell.selection = .session(id: $0) }
                        } else if shell.selection == .usage {
                            UsageView(store: AppUsage.store)
                        } else if shell.selection == .newSession {
                            NewSessionView(model: model.newSession, openHealth: shell.openHealth) { shell.selection = .session(id: $0) }
                        } else if let emptyPage {
                            EmptyStateView(state: emptyPage)
                        } else if case .session(let id) = shell.selection {
                            ConversationView(sessionId: id, draft: model.newSession, request: shell.conversationRequest, subagents: $shell.subagents, header: $shell.subagentHeader) { plan in
                                model.newSession.restore(plan)
                                shell.selection = .newSession
                            }.id(id)
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
                            StoppedView(state: model.state, openSettings: { shell.showSettings(.engine) })
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let target = activeDrawerTarget,
                       shell.isTerminalDrawerOpen(for: target.owner),
                       target.isSessionDrawer || terminalStore.tabs(for: target.owner).isEmpty == false {
                        TerminalDrawerView(
                            store: terminalStore,
                            owner: target.owner,
                            defaultDirectory: target.defaultDirectory,
                            openDefaultTabIfEmpty: target.isSessionDrawer,
                            dismissIcon: target.isSessionDrawer ? "chevron.down" : "xmark",
                            dismissLabel: target.isSessionDrawer ? "Hide terminal" : "Close terminal",
                            height: Binding(
                                get: { CGFloat(terminalDrawerHeight) },
                                set: { terminalDrawerHeight = Double($0) }
                            ),
                            maxHeight: max(220, windowSize.height * 0.6),
                            dismissDrawer: {
                                if target.isSessionDrawer {
                                    setDrawerOpen(false, for: target.owner)
                                } else {
                                    Task {
                                        guard await terminalStore.closeAll(for: target.owner) else { return }
                                        setDrawerOpen(false, for: target.owner)
                                    }
                                }
                            },
                            autoHideOnEmpty: {
                                setDrawerOpen(false, for: target.owner)
                            }
                        )
                        .id(target.owner)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                // only an epic has something to inspect; the other pages are a single column. The panel runs up behind the
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
            .themedWindowBackground()
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            // the subagent's own title is in the toolbar, as one item with the line that says whose it is
            .toolbar(removing: shell.subagentHeader == nil ? nil : .title)
            .onChange(of: model.shell.selection) { _, _ in
                if let target = activeDrawerTarget,
                   target.isSessionDrawer == false,
                   shell.isTerminalDrawerOpen(for: target.owner),
                   terminalStore.tabs(for: target.owner).isEmpty {
                    shell.setTerminalDrawerOpen(false, for: target.owner)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { withAnimation(.smooth(duration: 0.25)) { shell.toggleSidebar() } } label: { Label("Sidebar", systemImage: "sidebar.leading") }
                    .help("Show or hide the sidebar")
            }
            if isDevBuild {
                ToolbarItem(placement: .navigation) {
                    Text("DEV BUILD").font(.caption.weight(.bold)).foregroundStyle(.orange)
                        .help("A development build of Carrier, not the installed one")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            if let epic {
                ToolbarItem(placement: .primaryAction) { EpicLinks(prURL: epic.header.prURL, issueURL: epic.header.issueURL) }
                    .sharedBackgroundVisibility(.hidden)
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
            if let session = openSession {
                let drawerOpen = shell.isTerminalDrawerOpen(for: .session(session.id))
                if let open = shell.subagentHeader {
                    // a subagent view wears the window's header: Back next to the sidebar's button, its title, and its state where the worktree pill is
                    ToolbarItem(placement: .navigation) {
                        Button { shell.leaveSubagent() } label: { Label("Back", systemImage: "chevron.left") }
                            .help(shell.subagents.count > 1 ? "Back to the subagent that launched this one" : "Back to the conversation")
                    }
                    ToolbarItem(placement: .navigation) {
                        SubagentTitle(title: open.title, subtitle: open.subtitle(of: conversationTitle(session)))
                            .frame(maxWidth: windowSize.width * 0.35, alignment: .leading)
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .primaryAction) { SubagentStatePill(header: open) }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .primaryAction) { SessionPlacePill(row: session) }
                        .sharedBackgroundVisibility(.hidden)
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    ToolbarGlassIconButton(icon: drawerOpen ? "terminal.fill" : "terminal", name: drawerOpen ? "Hide terminal" : "Open terminal in \(abbreviatedTerminalPath(session.folder))") {
                        toggleSessionTerminal(for: session)
                    }
                    .glassEffect(.regular, in: .capsule)
                    .padding(.trailing, 10)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            if shell.selection == .usage {
                ToolbarItem(placement: .primaryAction) {
                    let checking = AppUsage.store.isRefreshing
                    ToolbarPillButton(title: checking ? "Checking…" : "Check again", icon: "arrow.clockwise", spinning: checking) { AppUsage.refresher.checkAgain() }
                        .glassEffect(.regular, in: .capsule)
                        .padding(.trailing, 10)
                        .disabled(checking)
                        .help("Asks every provider again, skipping the minute the chat host keeps its answer")
                }
                .sharedBackgroundVisibility(.hidden)
            }
            if let snapshot, shell.selection == .carrier {
                // two glass pills: the check against GitHub, then what governs Carrier itself (intake and stopping)
                ToolbarItem(placement: .primaryAction) {
                    // the engine polls on its own after the answer: the button says so until the next check is scheduled again
                    let checking = isChecking(snapshot, asked: checkAsked, now: Date())
                    ToolbarPillButton(title: checking ? "Checking…" : "Check now", icon: "arrow.clockwise", spinning: checking) {
                        checkAsked = CheckAsked(at: Date(), nextCheckAt: snapshot.nextCheckAt)
                        MenuControls.shared.checkNow()
                    }
                    .glassEffect(.regular, in: .capsule)
                    .disabled(checking)
                    .help(checking ? "Checking GitHub…" : "Check GitHub now")
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 0) {
                        ToolbarPillButton(title: snapshot.paused ? "Resume" : "Pause", icon: snapshot.paused ? "play.fill" : "pause.fill") { MenuControls.shared.pauseOrResume() }
                            .help(snapshot.paused ? "Resume intake" : "Pause intake")
                        ToolbarPillButton(title: "Stop", icon: "stop.fill", iconTint: .red) { MenuControls.shared.stopCarrier() }
                            .help("Stop Carrier")
                    }
                    .glassEffect(.regular, in: .capsule)
                    .padding(.trailing, 10)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        // reachable whatever Carrier is doing: it is where a stopped Carrier is made ready
        // what the engine answered to a save belongs to the engine that answered: another one, or none, starts clean
        .onChange(of: engineRunning) { ReloadStatus.shared.reset() }
        .sheet(isPresented: $shell.settingsShown) { SettingsSheet(state: model.state, canReload: model.epics.canReload, tab: $shell.settingsTab).themed() }
        .frame(minWidth: 1100, minHeight: 600)
        .themed()
        .environment(model.actions)
        .onChange(of: focus, initial: true) { model.epics.poller.show(focus) }
        .onChange(of: shell.archiveRequest) {
            guard let id = shell.archiveRequest?.sessionId else { return }
            // the shortcut has no button to be off: a session that works says why it is not archived, as the buttons do in their tooltip
            if let reason = model.sessions.rows.first(where: { $0.id == id }).flatMap(archiveBlock) { return tell(reason) }
            Task { if let refusal = await model.actions.archive(id) { tell(refusal) } }
        }
        .onChange(of: snapshot) {
            if let snapshot {
                model.epics.settleResuming(snapshot)
                for epic in snapshot.epics where epic.status == .running {
                    let owner = TerminalOwner.epic(repo: epic.repo, issue: epic.issue)
                    if terminalStore.tabs(for: owner).isEmpty == false {
                        terminalStore.forceCloseAll(for: owner)
                    }
                    if shell.isTerminalDrawerOpen(for: owner) {
                        shell.setTerminalDrawerOpen(false, for: owner)
                    }
                }
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { windowSize = $0 }
        .environment(\.windowSize, windowSize)
    }
}

private struct Running: View {
    let snapshot: PanelSnapshot
    @Binding var selection: Selection

    var body: some View {
        switch selection {
        case .carrier:
            Overview(snapshot: snapshot, selection: $selection)
        case .epic(let repo, let issue):
            // not in the snapshot (any more)
            Text("\(repo) #\(issue)")
        case .home, .sessions, .session, .newSession, .terminals, .terminal, .archive, .usage:
            EmptyView()  // PanelView shows these pages
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
