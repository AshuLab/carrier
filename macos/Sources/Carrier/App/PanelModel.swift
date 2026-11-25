import AppKit
import Observation
import CarrierCore
import SwiftUI

/// What the window shows: nil until the first answer from Carrier.
@Observable final class PanelModel {
    var state: ConnectionState? {
        // an epic that stops on a usage limit has used up a quota: the Usage page's numbers are asked again
        didSet {
            // counts what the window is handed: a clock that moved is one more
            Signposts.render.emitEvent("panel state")
            if usageLimitEntered(from: oldValue, to: state) { MainActor.assumeIsolated { _ = AppUsage.refresher.limitHit() } }
        }
    }
    let shell = WindowShell(open: SidebarStore().open)
    let epics = EpicStore()
    /// Archive, restore and delete; `startMonitor` makes the lists read again after each.
    let actions: SessionActions = {
        let actions = SessionActions(host: SocketChatHost())
        actions.confirmSessionRemoval = { kind, sessionIds in
            guard let store = CarrierTerminalStore.sharedIfInitialized,
                  let question = await store.pendingConfirmation(
                      for: .owners(sessionIds.map { .session($0) }),
                      removalKind: kind
                  )
            else {
                return true
            }
            return ask(question)
        }
        actions.didRemoveSession = { sessionId in
            CarrierTerminalStore.sharedIfInitialized?.forceCloseAll(for: .session(sessionId))
        }
        actions.forgetDeletedSessions(in: .userDefaults)
        return actions
    }()
    init() {
        // after the terminals of the session are closed, the window leaves it if it is the one on screen
        let closeTerminals = actions.didRemoveSession
        actions.didRemoveSession = { [shell] sessionId in
            closeTerminals(sessionId)
            shell.sessionRemoved(sessionId)
        }
    }

    var collapse = SidebarCollapse()
    /// The chat host's sessions (`ChatSessionsPoller`), with which of them are unread.
    var sessions = Sessions()
    /// When the person last saw each session (`SessionSeen`), and the list as the host gave it, before `unread`; nil until the host
    /// answered a list once.
    @ObservationIgnored private var seen = SessionSeen.stored()
    @ObservationIgnored private var hostRows: [SessionRow]?
    /// Holds the place of the sessions that work, so the lists do not move them with each event of their agents (`WorkingOrder`).
    @ObservationIgnored private var workOrder = WorkingOrder()

    /// A new list from the host, on the main thread.
    func adopt(_ rows: [SessionRow]) {
        hostRows = rows
        Task { await actions.learnHost() }
        refreshUnread()
    }

    /// The groups are titled with the projects' names, so a change of the projects sets the rows again. Called once the app is up.
    @MainActor func followProjects() {
        withObservationTracking { _ = ProjectsModel.shared.rows } onChange: { [weak self] in
            DispatchQueue.main.async { self?.refreshUnread(); MainActor.assumeIsolated { self?.followProjects() } }
        }
    }

    /// Prunes persisted/live session terminals only after two consecutive healthy chat-host polls omit them.
    @MainActor
    func reconcileKnownSessions(_ knownIds: Set<String>) {
        CarrierTerminalStore.lastKnownSessionIds = knownIds
        CarrierTerminalStore.sharedIfInitialized?.reconcileKnownSessions(knownIds)
    }

    /// Sets `unread` again: when the list changes and when the open session does. The session on screen is seen as it moves.
    func refreshUnread() {
        // before the host answered a list there is nothing to compare with: what was seen is neither pruned nor stored
        guard let listed = hostRows else { return }
        var rows = MainActor.assumeIsolated { retitled(listed, projects: ProjectsModel.shared.rows) }
        var viewing: String?
        if case .session(let id) = shell.selection { viewing = id }
        if seen.apply(to: &rows, viewing: viewing) { seen.store() }
        workOrder.apply(to: &rows)
        // a session the person just archived is drawn archived before the host's list says so
        actions.settle(listed)
        let leaving = actions.archiving
        for index in rows.indices where leaving.contains(rows[index].id) { rows[index].archived = true }
        if sessions.rows != rows { sessions.rows = rows }
    }

    /// Mark as unread or as read, from a session's menu. The session open on screen is seen as it moves, so its menu does not offer it.
    func setUnread(_ id: String, _ unread: Bool) {
        if unread { seen.markUnread([id]) } else { seen.markSeen(id, in: hostRows ?? []) }
        seen.store()
        refreshUnread()
    }

    /// New session on a branch, from a session's menu: the draft opens in the project, with a worktree cut from the branch when one is given.
    @MainActor func startNewSession(in base: String, branch: String?) {
        newSession.start(in: base, branch: branch)
        shell.selection = .newSession
    }

    /// The person leaves a session: what it did up to now is seen.
    func leave(_ id: String) {
        seen.markSeen(id, in: hostRows ?? [])
        refreshUnread()
    }
    /// The draft of a new session; it starts the chat host when it is not running (#503) before it opens the session.
    // built on the main thread, where the app creates its window
    let newSession = MainActor.assumeIsolated {
        NewSessionModel(host: SocketChatHost(), health: AppHealth.store, offers: .shared, ensureHost: {
            await withCheckedContinuation { continuation in ChatHostStarter.shared.ensureRunning { continuation.resume(returning: $0) } }
        }, send: EngineConfigSender.app.send, projects: .shared)
    }
}
