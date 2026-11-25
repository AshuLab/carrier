import AppKit
import CarrierCore
import SwiftUI

struct PanelView: View {
    private let timeChanges = TimeFormatChanges()
    let model: PanelModel
    // the sidebar's preferences are read from the defaults, so the sidebar's menus and the Sidebar page of Settings change one value
    @AppStorage(Preference.sidebarGroupBy) private var groupBy
    @AppStorage(Preference.sidebarSessionSort) private var sessionSort
    @AppStorage(Preference.sidebarArchiveSort) private var archiveSort
    @AppStorage(Preference.terminalDrawerHeight) private var terminalDrawerHeight
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    let terminalStore = CarrierTerminalStore.shared
    /// The last Check now pressed from the toolbar, for the button to say it is checking.
    @State var checkAsked: CheckAsked?
    /// The window's size, for the sheets over it.
    @State var windowSize = CGSize(width: 1100, height: 700)
    /// The right panel's width: also the empty toolbar item that keeps the epic's buttons off it.
    static let inspectorWidth: CGFloat = 316

    var snapshot: PanelSnapshot? {
        if case .running(let snapshot)? = model.state { return snapshot }
        return nil
    }

    /// The selected epic when it is in the snapshot.
    var epic: (subject: EpicSubject, header: EpicHeader, now: Int)? {
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
        var focus = epicFocus(ref, running: running, data: model.epics.data[ref], folds: model.epics.folds, filesShown: model.epics.filesTabShown)
        focus.openFiles = model.epics.filesTabShown ? model.epics.openFiles[ref] ?? [] : []
        return focus
    }

    /// The toolbar's title and the line under it, as in the mockup: each screen says what it is.
    private var title: String {
        if let epic { return "\(epic.subject.repo.split(separator: "/").last ?? "") #\(epic.subject.issue)" }
        switch model.shell.selection {
        case .sessions: return Copy.sidebarSessions()
        case .session: return openSession.map { conversationTitle($0) } ?? Copy.epicsPanelSession()
        case .newSession: return Copy.sessionsNew()
        case .terminals: return Copy.epicsPanelTerminal()
        case .terminal(let id): return terminalStore.standaloneTerminal(id: id)?.title ?? Copy.epicsPanelTerminal()
        case .archive: return Copy.archiveTitle()
        case .usage: return Copy.sidebarUsage()
        default: return Copy.appName()
        }
    }

    /// The row of the session whose conversation is open.
    var openSession: SessionRow? {
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
        case .usage: Copy.epicsPanelUsageSubtitle()
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

    var body: some View {
        let _ = Signposts.render.emitEvent("PanelView body")
        @Bindable var shell = model.shell
        @Bindable var epics = model.epics
        let collapse = Binding(get: { model.collapse }, set: { model.collapse = $0 })
        let columns = Binding<NavigationSplitViewVisibility>(
            get: { shell.sidebarShown ? .all : .detailOnly }, set: { shell.sidebarShown = $0 != .detailOnly }
        )
        NavigationSplitView(columnVisibility: columns) {
            SidebarView(snapshot: snapshot, state: model.state, sessions: model.sessions, terminalStore: terminalStore, selection: $shell.selection, open: $shell.open, groupBy: $groupBy, sessionSort: $sessionSort, collapse: collapse, searchRequest: shell.searchRequest, chooseArchived: shell.chooseArchived, openSettings: { WindowController.shared.showSettings() }, newSessionIn: { path in
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
                .onChange(of: terminalStore.standaloneTerminals().map(\.id)) { old, new in
                    // the selection leaves a closed terminal first, so the history can forget it
                    reconcileSelectedTerminal()
                    for gone in Set(old).subtracting(new) { model.shell.terminalRemoved(gone) }
                }
                // the logo (the mark, centred) is drawn over the title bar at an exact place, clear of the window's buttons and of the update, which stays at the right edge
                .overlay(alignment: .top) { BrandLogo().ignoresSafeArea(edges: .top).allowsHitTesting(false) }
                .toolbar {
                    ToolbarSpacer(.flexible, placement: .automatic)
                    UpdatePill.item(AppUpdater.shared)
                }
        } detail: {
            // the right panel is ours, not `.inspector`: that one, inside a NavigationSplitView, loops AppKit's layout while the window
            // resizes and the app dies with "more Update Constraints passes than there are views"
            HStack(spacing: Tokens.Space.none) {
                VStack(spacing: Tokens.Space.none) {
                    Group {
                        if let epic {
                            let ref = EpicRef(repo: epic.subject.repo, issue: epic.subject.issue)
                            let data = model.epics.data[ref]
                            let over: Bool = if case .ended = epic.subject { true } else { false }
                            EpicView(
                                subject: epic.subject, reply: data?.epic, filesChanged: data?.filesChanged.fileCount ?? 0,
                                sessions: sessionList(data?.sessions, transcripts: data?.transcripts ?? [:], slices: data?.epic?.slices ?? [], now: epic.now, resumable: over == false, folds: epics.folds), folds: $epics.folds, subagents: $shell.subagents, subagentHeader: $shell.subagentHeader, filesModel: data?.filesChanged ?? .empty,
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
                            NewSessionView(model: model.newSession, openHealth: { WindowController.shared.showSettings(.health) }, opened: { shell.selection = .session(id: $0) }, request: shell.conversationRequest)
                        } else if let emptyPage {
                            EmptyStateView(state: emptyPage).inPageScroll()
                        } else if case .session(let id) = shell.selection {
                            ConversationView(sessionId: id, draft: model.newSession, request: shell.conversationRequest, subagents: $shell.subagents, header: $shell.subagentHeader) { plan in
                                model.newSession.restore(plan)
                                shell.selection = .newSession
                            }.id(id)
                        } else if case .running(let snapshot)? = model.state {
                            ScrollView {
                                VStack(alignment: .leading, spacing: Tokens.Space.s24) {
                                    Running(snapshot: snapshot, selection: $shell.selection)
                                }
                                .padding(Tokens.Space.s18)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                            }
                        } else {
                            // Carrier is not answering (or has not yet): what to do about it
                            StoppedView(state: model.state, openSettings: { WindowController.shared.showSettings(.engine) })
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
                            dismissIcon: target.isSessionDrawer ? .chevronDown : .close,
                            dismissLabel: target.isSessionDrawer ? Copy.epicsToolbarHideTerminal() : Copy.epicsPanelCloseTerminal(),
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
                    HStack(spacing: Tokens.Space.none) {
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
            // the subagent's own title is in the toolbar, as one item with the line that says whose it is; the system's is left empty and not removed,
            // because it is what fills the toolbar between its two ends and keeps the buttons at the right
            .navigationTitle(shell.subagentHeader == nil ? title : "")
            .navigationSubtitle(shell.subagentHeader == nil ? subtitle : "")
            .onChange(of: model.shell.selection) { _, _ in
                if let target = activeDrawerTarget,
                   target.isSessionDrawer == false,
                   shell.isTerminalDrawerOpen(for: target.owner),
                   terminalStore.tabs(for: target.owner).isEmpty {
                    shell.setTerminalDrawerOpen(false, for: target.owner)
                }
            }
        }
        .toolbar { panelToolbar }
        // reachable whatever Carrier is doing: it is where a stopped Carrier is made ready
        // what the engine answered to a save belongs to the engine that answered: another one, or none, starts clean
        .onChange(of: engineRunning) { ReloadStatus.shared.reset() }
        .frame(minWidth: 1100, minHeight: 600)
        .themed()
        .environment(model.actions)
        .onChange(of: focus, initial: true) { model.epics.poller.show(focus) }
        .onChange(of: shell.archiveRequest) {
            guard let id = shell.archiveRequest?.sessionId else { return }
            // the shortcut has no button to be off: a session that works says why it is not archived, as the buttons do in their tooltip
            if let reason = model.sessions.rows.first(where: { $0.id == id }).flatMap { archiveBlock($0) } { return tell(reason) }
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
