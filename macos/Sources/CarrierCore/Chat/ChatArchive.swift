import Foundation

// The Archive page (docs/specs/sessions-in-the-app.md, "Archive"): what it lists and says as plain values, the menu of a session row,
// the questions it asks, and what archiving, restoring, deleting and clearing do through the chat host.

/// How the Archive is ordered. The host does not say when a session was archived (it only archives an idle one), so "date archived"
/// is the session's last activity.
public enum ArchiveSort: String, CaseIterable { case dateArchived, project }

/// What the page shows for the archived rows: the groups, the count under the title, which empty state when there is nothing to list,
/// whether Clear sessions has something to delete, and the line under a row (by session id) for the ones that have one.
public struct ArchivePage: Equatable {
    public var subtitle: String
    public var groups: [SessionGroup]
    public var notes: [String: String] = [:]
    public var emptyState: EmptyState?
    public var canClear: Bool
}

/// The line under an archived row: why a kept session is still there, else when the clock deletes it ("Deletes in 12 days", counted up
/// to whole days from `now`, "Deletes soon" when it is due); nil when the host gave no date.
public func archiveNote(_ row: SessionRow, now: Date = Date(), bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    if row.kept { return Copy.archiveNoteKept(bundle: bundle, locale: locale) }
    guard let deleteAt = row.deleteAt else { return nil }
    let days = Int((deleteAt.timeIntervalSince(now) / 86400).rounded(.up))
    return days <= 0 ? Copy.archiveNoteDeletesSoon(bundle: bundle, locale: locale) : Copy.archiveNoteDeletesIn(days: days, bundle: bundle, locale: locale)
}

/// The archived rows only. By date archived: Last 30 days and Older (counted back from `now`); by project: one group per workspace
/// ordered by name ignoring case; newest first inside a group. A non-empty `query` matches the title, the workspace and the agent
/// ignoring case and lists the matches, newest first, in one group. `notes` is `archiveNote` of each archived row. The subtitle is "5 sessions" ("2 results" while searching) and
/// says nothing when nothing is archived; the page is "Nothing archived" then, "No sessions match" when a search finds none.
public func archivePage(
    _ rows: [SessionRow], by sort: ArchiveSort = .dateArchived, query: String = "", now: Date = Date(), bundle: Bundle? = nil, locale: Locale = .current
) -> ArchivePage {
    let archived = rows.filter(\.archived)
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    let newest: (SessionRow, SessionRow) -> Bool = { $0.updatedAt > $1.updatedAt }
    func group(_ title: String, _ rows: [SessionRow]) -> SessionGroup? { rows.isEmpty ? nil : SessionGroup(title: title, rows: rows.sorted(by: newest)) }
    let groups: [SessionGroup]
    if query.isEmpty == false {
        let found = archived.filter { [$0.title, $0.workspace, $0.agent].contains { $0.localizedCaseInsensitiveContains(query) } }
        groups = group(Copy.sessionGroupResults(bundle: bundle, locale: locale), found).map { [$0] } ?? []
    } else {
        switch sort {
        case .dateArchived:
            let cutoff = now.addingTimeInterval(-30 * 86400)
            groups = [
                group(Copy.archiveGroupLast30Days(bundle: bundle, locale: locale), archived.filter { $0.updatedAt >= cutoff }),
                group(Copy.sessionGroupOlder(bundle: bundle, locale: locale), archived.filter { $0.updatedAt < cutoff }),
            ].compactMap { $0 }
        case .project:
            groups = Dictionary(grouping: archived, by: \.workspace).compactMap { group($0.key, $0.value) }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
    }
    let shown = groups.reduce(0) { $0 + $1.rows.count }
    let subtitle = query.isEmpty == false
        ? Copy.sessionsResultCount(count: shown, bundle: bundle, locale: locale)
        : archived.isEmpty ? "" : Copy.sessionsCount(count: archived.count, bundle: bundle, locale: locale)
    let empty: EmptyState? = groups.isEmpty ? (archived.isEmpty ? .nothingArchived : .noSessionsMatch) : nil
    let notes = Dictionary(uniqueKeysWithValues: archived.compactMap { row in archiveNote(row, now: now, bundle: bundle, locale: locale).map { (row.id, $0) } })
    return ArchivePage(subtitle: subtitle, groups: groups, notes: notes, emptyState: empty, canClear: archived.isEmpty == false)
}

/// What an alert says; its first button is the one that does nothing, and the default.
public struct Question: Equatable {
    public let title: String
    public let message: String
    public let confirm: String

    public init(title: String, message: String, confirm: String) {
        self.title = title
        self.message = message
        self.confirm = confirm
    }
}

/// What a worktree holds that deleting would lose, in words: "3 uncommitted files and 2 commits that exist nowhere else"; nil when it holds nothing.
private func lostWork(files: Int, commits: Int, bundle: Bundle?, locale: Locale) -> String? {
    switch (files > 0, commits > 0) {
    case (true, true): Copy.archiveLostBoth(files: files, commits: commits, bundle: bundle, locale: locale)
    case (true, false): Copy.archiveLostFiles(count: files, bundle: bundle, locale: locale)
    case (false, true): Copy.archiveLostCommits(count: commits, bundle: bundle, locale: locale)
    case (false, false): nil
    }
}

/// Clear sessions: names how many will be deleted and, from the host's `deletePreview` of all of them, how many work in a worktree
/// that would lose work and the totals of files and commits; sessions in a base folder add nothing.
public func clearSessionsQuestion(count: Int, previews: [SessionDeletePreview] = [], bundle: Bundle? = nil, locale: Locale = .current) -> Question {
    let worktrees = previews.compactMap(\.worktree)
    let losing = worktrees.filter { $0.dirty + $0.unpushed > 0 }
    var message = Copy.archiveClearMessage(bundle: bundle, locale: locale)
    if let lost = lostWork(files: losing.reduce(0) { $0 + $1.dirty }, commits: losing.reduce(0) { $0 + $1.unpushed }, bundle: bundle, locale: locale) {
        message = Copy.archiveClearMessageLosing(count: losing.count, lost: lost, bundle: bundle, locale: locale)
    } else if worktrees.isEmpty == false {
        message = Copy.archiveClearMessageWorktrees(count: worktrees.count, bundle: bundle, locale: locale)
    }
    return Question(
        title: Copy.archiveClearTitle(count: count, bundle: bundle, locale: locale), message: message, confirm: Copy.archiveClearConfirm(count: count, bundle: bundle, locale: locale)
    )
}

/// Delete on one row, with what the host says its worktree holds (nil for a session in a base folder, which keeps the plain text) and, first, what
/// it stops when the session has processes.
public func deleteSessionQuestion(_ row: SessionRow, worktree: SessionDeletePreview.Worktree? = nil, bundle: Bundle? = nil, locale: Locale = .current) -> Question {
    var message = Copy.archiveDeleteMessage(bundle: bundle, locale: locale)
    if let worktree {
        message = lostWork(files: worktree.dirty, commits: worktree.unpushed, bundle: bundle, locale: locale)
            .map { Copy.archiveDeleteMessageLosing(lost: $0, bundle: bundle, locale: locale) } ?? Copy.archiveDeleteMessageWorktree(bundle: bundle, locale: locale)
    }
    let processes = processesStopped(row)
    if processes.isEmpty == false { message = "\(stopsMessage(processes, bundle: bundle, locale: locale))\n\(message)" }
    return Question(title: Copy.archiveDeleteTitle(title: row.title, bundle: bundle, locale: locale), message: message, confirm: Copy.sessionDelete(bundle: bundle, locale: locale))
}

/// What replaces the message box of an archived session, beside its Resume button.
public func archivedSessionNotice(bundle: Bundle? = nil, locale: Locale = .current) -> (title: String, detail: String) {
    (Copy.chatArchivedTitle(bundle: bundle, locale: locale), Copy.chatArchivedDetail(bundle: bundle, locale: locale))
}

public enum SessionMenuAction: Equatable {
    case stop, pin, unpin, rename, regenerateTitle, openInTerminal(path: String), filterWorkspace(String), archive, restore, delete
    case markUnread, markRead
    /// A new session in the project at `base`, cut from `branch` in a worktree when it is given.
    case newSession(base: String, branch: String?)
    /// The project's page in Settings; `base` is the project's folder.
    case openProject(base: String)
    case copy(String)
}

/// One line of the menu: a button with `action`, or a submenu of `children` (no action).
public struct SessionMenuItem: Equatable {
    public let title: String
    /// The SF Symbol drawn beside the title.
    public let icon: String
    public let action: SessionMenuAction?
    public var children: [SessionMenuItem] = []
    public var destructive = false
    /// Why the item cannot be used now, in words for its tooltip; nil while it can.
    public var disabledReason: String?

    init(_ title: String, _ icon: String, _ action: SessionMenuAction?, children: [SessionMenuItem] = [], destructive: Bool = false, disabledReason: String? = nil) {
        (self.title, self.icon, self.action, self.children, self.destructive, self.disabledReason) = (title, icon, action, children, destructive, disabledReason)
    }
}

/// Why a session cannot be archived now, nil when it can: the host refuses one that works, waits for an answer or has agent work running in the
/// background, so the buttons say it beforehand and are off, and the person knows to stop it first. A background process does not block it: the
/// archive stops it (`processesStopped`).
public func archiveBlock(_ row: SessionRow, bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    switch row.state {
    case .working: Copy.archiveBlockWorking(bundle: bundle, locale: locale)
    case .waiting: Copy.archiveBlockWaiting(bundle: bundle, locale: locale)
    case .idle, .done: agentWorkCount(row) == 0 ? nil : Copy.archiveBlockBackground(count: agentWorkCount(row), bundle: bundle, locale: locale)
    }
}

private func agentWorkCount(_ row: SessionRow) -> Int { row.background.filter(\.agentWork).count }

/// The background processes an archive or a delete of the session would stop, in the order the host lists them; none for a session with no
/// process, and none for one the host refuses anyway (it stops nothing then).
public func processesStopped(_ row: SessionRow) -> [BackgroundTask] {
    archiveBlock(row) == nil ? row.processes : []
}

/// What an archive or a delete says it stops: up to three names, then "+n more", as the hover card does ("pnpm dev, tsc +2 more").
func stopsMessage(_ processes: [BackgroundTask], bundle: Bundle? = nil, locale: Locale = .current) -> String {
    let shown = processes.prefix(3).map(\.name).joined(separator: ", ")
    let more = processes.count - 3
    let names = more > 0 ? "\(shown) \(Copy.chatPeekMoreTasks(count: more, bundle: bundle, locale: locale))" : shown
    return Copy.archiveStopsMessage(names: names, bundle: bundle, locale: locale)
}

/// What is asked before archiving a session that has processes, naming what the archive stops; nil for one with none, which is archived without asking.
public func archiveStopsQuestion(_ row: SessionRow, bundle: Bundle? = nil, locale: Locale = .current) -> Question? {
    let processes = processesStopped(row)
    guard processes.isEmpty == false else { return nil }
    return Question(title: Copy.archiveStopsTitle(title: row.title, bundle: bundle, locale: locale), message: stopsMessage(processes, bundle: bundle, locale: locale), confirm: Copy.sessionArchive(bundle: bundle, locale: locale))
}

/// Why a session cannot be deleted now, nil when it can: the host refuses one that works, waits or has agent work in the background, as it does an
/// archive, and its worktree cannot be removed under a running agent.
public func deleteBlock(_ row: SessionRow, bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    switch row.state {
    case .working: Copy.deleteBlockWorking(bundle: bundle, locale: locale)
    case .waiting: Copy.deleteBlockWaiting(bundle: bundle, locale: locale)
    case .idle, .done: agentWorkCount(row) == 0 ? nil : Copy.deleteBlockBackground(count: agentWorkCount(row), bundle: bundle, locale: locale)
    }
}

/// What the menu of a session can offer that depends on where it is drawn: the sidebar and the home have each of these, the Archive has few.
public struct SessionMenuContext: Equatable {
    /// Mark as unread or as read. Not for an archived session, and off for the one that is open (opening it marks it read).
    public var marksUnread = false
    /// The session is the one open on screen.
    public var viewing = false
    /// New session on its branch (or in its project), which opens the draft.
    public var startsSessions = false
    /// Its project is in Carrier's list, so Project settings has a page to open.
    public var projectKnown = false

    public init(marksUnread: Bool = false, viewing: Bool = false, startsSessions: Bool = false, projectKnown: Bool = false) {
        (self.marksUnread, self.viewing, self.startsSessions, self.projectKnown) = (marksUnread, viewing, startsSessions, projectKnown)
    }
}

/// The title of New session for a row: its branch (shortened in the middle when long), or the project when it works in the folder itself.
public func newSessionTitle(_ row: SessionRow, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    guard let branch = row.branch else { return Copy.sessionMenuNewInProject(bundle: bundle, locale: locale) }
    let limit = 34
    guard branch.count > limit else { return Copy.sessionMenuNewOnBranch(branch: branch, bundle: bundle, locale: locale) }
    let head = branch.prefix(limit / 2 - 1), tail = branch.suffix(limit / 2)
    return Copy.sessionMenuNewOnBranch(branch: "\(head)\u{2026}\(tail)", bundle: bundle, locale: locale)
}

/// The context menu of a session row in the sidebar, on the Sessions home and in the Archive, as sections the view separates with a
/// divider: Stop (while it works) and Pin; Rename and, while the host lists `regenerateTitle` (`canRegenerateTitle`), Regenerate title; Open in Terminal, Copy (path, branch name, session id) and, where the
/// view can filter (`canFilter`, the home), Filter by the workspace; Archive (Restore for an archived one) and Delete (off while it works or waits).
/// `context` adds what only some views can do: Mark as unread, New session on its branch and Project settings.
/// An archived session is not listed in the groups, so it has no Pin.
public func sessionMenu(
    _ row: SessionRow, pinned: Bool = false, canFilter: Bool = false, canRegenerateTitle: Bool = false, context: SessionMenuContext = SessionMenuContext(),
    bundle: Bundle? = nil, locale: Locale = .current
) -> [[SessionMenuItem]] {
    var copies = [SessionMenuItem(Copy.sessionMenuPath(bundle: bundle, locale: locale), "folder", .copy(row.folder))]
    if let branch = row.branch { copies.append(SessionMenuItem(Copy.sessionMenuBranchName(bundle: bundle, locale: locale), "arrow.triangle.branch", .copy(branch))) }
    copies.append(SessionMenuItem(Copy.sessionMenuSessionId(bundle: bundle, locale: locale), "number", .copy(row.id)))

    var control: [SessionMenuItem] = []
    if row.isWorking { control.append(SessionMenuItem(Copy.sessionMenuStop(bundle: bundle, locale: locale), "stop.circle", .stop)) }
    if row.archived == false {
        control.append(
            pinned ? SessionMenuItem(Copy.sessionUnpin(bundle: bundle, locale: locale), "pin.slash", .unpin) : SessionMenuItem(Copy.sessionPin(bundle: bundle, locale: locale), "pin", .pin)
        )
    }
    if context.marksUnread, row.archived == false {
        let reason = context.viewing ? Copy.sessionMenuMarkWhy(bundle: bundle, locale: locale) : nil
        control.append(
            row.unread
                ? SessionMenuItem(Copy.sessionMenuMarkRead(bundle: bundle, locale: locale), "circle", .markRead, disabledReason: reason)
                : SessionMenuItem(Copy.sessionMenuMarkUnread(bundle: bundle, locale: locale), "circle.fill", .markUnread, disabledReason: reason)
        )
    }
    var open: [SessionMenuItem] = []
    if context.startsSessions, row.archived == false {
        open.append(SessionMenuItem(newSessionTitle(row, bundle: bundle, locale: locale), row.branch == nil ? "plus" : "arrow.triangle.branch", .newSession(base: row.base, branch: row.branch)))
    }
    if context.projectKnown { open.append(SessionMenuItem(Copy.sessionMenuProjectSettings(bundle: bundle, locale: locale), "gearshape", .openProject(base: row.base))) }
    open += [
        SessionMenuItem(Copy.sessionMenuOpenInTerminal(bundle: bundle, locale: locale), "terminal", .openInTerminal(path: row.folder)),
        SessionMenuItem(Copy.sessionMenuCopy(bundle: bundle, locale: locale), "doc.on.doc", nil, children: copies),
    ]
    if canFilter {
        open.append(SessionMenuItem(Copy.sessionMenuFilterBy(workspace: row.workspace, bundle: bundle, locale: locale), "line.3.horizontal.decrease", .filterWorkspace(row.workspace)))
    }
    let end = [
        row.archived
            ? SessionMenuItem(Copy.sessionRestore(bundle: bundle, locale: locale), "arrow.uturn.backward", .restore)
            : SessionMenuItem(Copy.sessionArchive(bundle: bundle, locale: locale), "archivebox", .archive, disabledReason: archiveBlock(row, bundle: bundle, locale: locale)),
        SessionMenuItem(Copy.sessionMenuDelete(bundle: bundle, locale: locale), "trash", .delete, destructive: true, disabledReason: deleteBlock(row, bundle: bundle, locale: locale)),
    ]
    var title = [SessionMenuItem(Copy.sessionMenuRename(bundle: bundle, locale: locale), "pencil", .rename)]
    if canRegenerateTitle { title.append(SessionMenuItem(Copy.sessionMenuRegenerateTitle(bundle: bundle, locale: locale), "sparkles", .regenerateTitle)) }
    return [
        control,
        title,
        open,
        end,
    ].filter { $0.isEmpty == false }
}
