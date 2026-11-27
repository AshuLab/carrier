import Foundation

// The sidebar's content as plain values: the groups, their rows and detail lines, the pill and the remembered grouping
// (docs/specs/macos-app-redesign.md, stories 11 and 12). The views map them one to one.

public enum GroupBy: String, CaseIterable {
    case status, repo
}

/// The ids in the stored `Preference.sidebarPinned`.
public func pinnedIds(_ stored: String) -> Set<String> { Set(stored.split(separator: ",").map(String.init)) }

/// The string to store for these ids.
public func storedPins(_ ids: Set<String>) -> String { ids.sorted().joined(separator: ",") }

/// The grouping, the Sessions and Archive sorts and the unfolded section, kept in user defaults so they survive a relaunch.
public struct SidebarStore {
    /// How narrow and how wide the sidebar can be dragged, in points, and the width it opens at until the person moves it.
    public static let widthRange: ClosedRange<Double> = 280...800
    public static let defaultWidth = Preference.sidebarWidth.defaultValue

    private let preferences: AppPreferences

    public init(defaults: UserDefaults = .standard) { preferences = AppPreferences(defaults: defaults) }

    public var groupBy: GroupBy {
        get { preferences.value(Preference.sidebarGroupBy) }
        nonmutating set { preferences.store(newValue, for: Preference.sidebarGroupBy) }
    }

    public var sessionSort: SessionSort {
        get { preferences.value(Preference.sidebarSessionSort) }
        nonmutating set { preferences.store(newValue, for: Preference.sidebarSessionSort) }
    }

    public var pinned: Set<String> {
        get { pinnedIds(preferences.value(Preference.sidebarPinned)) }
        nonmutating set { preferences.store(storedPins(newValue), for: Preference.sidebarPinned) }
    }

    public var archiveSort: ArchiveSort {
        get { preferences.value(Preference.sidebarArchiveSort) }
        nonmutating set { preferences.store(newValue, for: Preference.sidebarArchiveSort) }
    }

    /// The width the person left the sidebar at, kept inside `widthRange`; `defaultWidth` until they move it.
    public var width: Double {
        get { Self.clamped(preferences.value(Preference.sidebarWidth)) }
        nonmutating set { preferences.store(Self.clamped(newValue), for: Preference.sidebarWidth) }
    }

    private static func clamped(_ width: Double) -> Double { min(max(width, widthRange.lowerBound), widthRange.upperBound) }

    /// The slots total the engine last reported, for the bars of a stopped engine; nil until one was seen.
    public var slotsTotal: Int? {
        get { preferences.value(Preference.sidebarSlotsTotal) }
        nonmutating set { preferences.store(newValue, for: Preference.sidebarSlotsTotal) }
    }

    /// The unfolded section. Both folded is stored as "none"; a value that is not a section brings back Sessions.
    public var open: OpenSection? {
        get {
            let stored = preferences.value(Preference.sidebarOpen)
            return stored == "none" ? nil : OpenSection(rawValue: stored) ?? .sessions
        }
        nonmutating set { preferences.store(newValue?.rawValue ?? "none", for: Preference.sidebarOpen) }
    }
}

/// What a session row shows besides its title: each part is on until the person switches it off in Settings.
public struct SessionRowParts: Equatable {
    public var icon = true
    public var branch = true
    public var providers = true
    public var age = true
    /// The third line: the pull request's chip, and the lines the session changed.
    public var pullRequest = true
    public var diff = true

    public init(icon: Bool = true, branch: Bool = true, providers: Bool = true, age: Bool = true, pullRequest: Bool = true, diff: Bool = true) {
        (self.icon, self.branch, self.providers, self.age, self.pullRequest, self.diff) = (icon, branch, providers, age, pullRequest, diff)
    }
}

/// Where a session works, as its row says it.
public enum SessionPlace: Equatable {
    case branch(String), baseFolder
}

/// A session row as the view draws it: the title is always there, the rest follows `parts`. `workspace` is the second line's first
/// part, only outside the workspace order (`showsWorkspace`), where the group is not the workspace; the place goes with the branch switch.
public struct SessionRowContent: Equatable {
    public var showsIcon: Bool
    public var workspace: String?
    public var place: SessionPlace?
    public var age: String?
    public var providers: [String]
    /// The pull request's chip, and the lines changed, that the third line has (nil while switched off, or when the session has none or the host
    /// has not read them). The row has a third line when it has either; with neither it has two.
    public var pullRequest: SessionPullRequest?
    public var diff: SessionDiff?
    /// How many background processes the session has: the still mark at the right of the second line, none when it has none.
    public var processes: Int

    public var hasThirdLine: Bool { pullRequest != nil || diff != nil }

    public init(_ row: SessionRow, showsWorkspace: Bool, parts: SessionRowParts, now: Date) {
        showsIcon = parts.icon
        workspace = showsWorkspace ? row.workspace : nil
        place = parts.branch ? row.branch.map(SessionPlace.branch) ?? .baseFolder : nil
        age = parts.age ? timeText(row.updatedAt, now: now) : nil
        providers = parts.providers ? row.providers : []
        pullRequest = parts.pullRequest ? row.pullRequest : nil
        diff = parts.diff ? row.diff : nil
        processes = row.processes.count
    }

    /// "2 background processes" for VoiceOver; nil with none.
    public func processesSpoken(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        processes > 0 ? Copy.sessionProcessesSpoken(count: processes, bundle: bundle, locale: locale) : nil
    }
}

public struct SidebarRow: Equatable {
    public var repo: String
    public var issue: Int
    public var state: EpicMenuState
    /// The epic's title; nil while the engine has none, and the view then shows `name` in its place.
    public var title: String?
    /// The repository's name, never its owner.
    public var name: String
    /// The one thing that matters in its state: why it stopped, what the agent is doing, what it waits for, or its PR.
    public var detail: String
    /// On the right of the first line, as a session's: "now", "5m", "3h", "2d"; how long in the state, empty when the engine has no time.
    public var age: String
    /// Only for a stuck epic: decides the colour of its glyph and of `detail`.
    public var attention: Attention?
    /// What opens when the pointer rests on the row.
    public var card: EpicCard

    public var selection: Selection { .epic(repo: repo, issue: issue) }
}

/// What a sidebar section's list says: it has rows, has nothing to list, or has rows but none match what was typed. `shown` is how
/// many rows the query leaves, `total` how many the list has without it.
public enum SidebarListState: Equatable {
    case rows, empty
    case noMatch(query: String)

    public init(shown: Int, of total: Int, query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if shown > 0 {
            self = .rows
        } else if total > 0 && query.isEmpty == false {
            self = .noMatch(query: query)
        } else {
            self = .empty
        }
    }
}

public struct SidebarGroup: Equatable {
    public var title: String
    public var rows: [SidebarRow]
    /// Whether the group is collapsed until the user opens it: Done and Cancelled.
    public var startsCollapsed = false

    /// Shown on the group's header.
    public var count: Int { rows.count }
}

/// What the user collapsed or expanded, by group title and grouping, kept while the app runs (not across launches). A group that
/// has no choice yet follows its `startsCollapsed`; a group that leaves the sidebar and returns keeps the choice made.
public struct SidebarCollapse: Equatable {
    private var chosen: [String: Bool] = [:]

    public init() {}

    public func isCollapsed(_ group: SidebarGroup, by groupBy: GroupBy) -> Bool {
        chosen[Self.key(group, groupBy)] ?? group.startsCollapsed
    }

    /// Whether the list shows `group` folded while `query` is typed: never, because every group left by a query has a match. The
    /// choice itself is kept, so clearing the query brings back what the user had.
    public func isCollapsed(_ group: SidebarGroup, by groupBy: GroupBy, query: String) -> Bool {
        query.trimmingCharacters(in: .whitespaces).isEmpty && isCollapsed(group, by: groupBy)
    }

    public mutating func toggle(_ group: SidebarGroup, by groupBy: GroupBy) {
        chosen[Self.key(group, groupBy)] = !isCollapsed(group, by: groupBy)
    }

    private static func key(_ group: SidebarGroup, _ groupBy: GroupBy) -> String { "\(groupBy.rawValue)/\(group.title)" }
}

/// The groups for `snapshot`. By status: needs you, running, up next, then ready for test, done and cancelled (each hidden when
/// empty; done and cancelled start collapsed), rows in the snapshot's order, finished ones newest first as the engine sends them.
/// By repository: sections ordered by name, rows by issue number, with no finished epics.
/// A non-empty `query` keeps the rows whose title, issue number (with or without `#`) or `owner/name` contain it, ignoring case, and
/// hides the groups left empty; an empty one changes nothing. Grouped by repository, a query also looks through the finished epics,
/// so Done and Cancelled are reachable in both groupings.
public func sidebarGroups(_ snapshot: PanelSnapshot, by groupBy: GroupBy, query: String = "", bundle: Bundle? = nil, locale: Locale = .current) -> [SidebarGroup] {
    let needle = query.trimmingCharacters(in: .whitespaces)
    let groups = allSidebarGroups(snapshot, by: groupBy, withFinished: needle.isEmpty == false, bundle: bundle, locale: locale)
    guard needle.isEmpty == false else { return groups }
    let number = needle.hasPrefix("#") ? String(needle.dropFirst()) : needle
    func matches(_ row: SidebarRow) -> Bool {
        (row.title?.localizedCaseInsensitiveContains(needle) ?? false) || row.repo.localizedCaseInsensitiveContains(needle)
            || (number.isEmpty == false && String(row.issue).contains(number))
    }
    return groups.compactMap { group in
        var kept = group
        kept.rows = group.rows.filter(matches)
        return kept.rows.isEmpty ? nil : kept
    }
}

/// `withFinished` adds the finished epics to the repository sections; the status grouping always has them as Done and Cancelled.
private func allSidebarGroups(_ snapshot: PanelSnapshot, by groupBy: GroupBy, withFinished: Bool, bundle: Bundle?, locale: Locale) -> [SidebarGroup] {
    let titles = Dictionary(
        uniqueKeysWithValues: (snapshot.epics.map { (key($0.repo, $0.issue), $0.title) } + snapshot.queue.map { (key($0.repo, $0.issue), $0.title) })
    )
    func row(
        _ subject: EpicSubject, _ state: EpicMenuState, _ detail: String, since: Int?, title own: String? = nil, attention: Attention? = nil
    ) -> SidebarRow {
        let (repo, issue) = (subject.repo, subject.issue)
        let title = (own ?? titles[key(repo, issue)].flatMap { $0 }).flatMap { $0.isEmpty ? nil : $0 }
        return SidebarRow(
            repo: repo, issue: issue, state: state, title: title, name: shortName(repo), detail: detail,
            age: since.map { timeText(Date(ms: $0), now: Date(ms: snapshot.now), bundle: bundle) } ?? "",
            attention: attention, card: epicCard(subject, now: snapshot.now)
        )
    }
    func finished(_ status: PanelSnapshot.FinishedEpic.Status) -> [SidebarRow] {
        snapshot.finished.filter { $0.status == status }.map { epic in
            guard status == .cancelled else {
                let merged = epic.prNumber.map { Copy.sidebarPrMerged(number: String($0), bundle: bundle, locale: locale) } ?? Copy.sidebarMerged(bundle: bundle, locale: locale)
                return row(.ended(epic), .done, merged, since: epic.finishedAt, title: epic.title)
            }
            let reason = epic.cancelReason.flatMap { $0.isEmpty ? nil : $0 }
            return row(.ended(epic), .cancelled, reason ?? Copy.sidebarCancelled(bundle: bundle, locale: locale), since: epic.finishedAt, title: epic.title)
        }
    }

    /// What the epic's agent did last, while it runs: the line a person wants most of a running epic.
    func doing(_ epic: PanelEpic) -> String? {
        epic.executionId.flatMap { id in snapshot.sessions?.first { $0.executionId == id }?.last?.text }.flatMap { $0.isEmpty ? nil : $0 }
    }
    let needsYou = snapshot.epics.filter { $0.status == .needsHuman }.map {
        row(.active($0), .needsYou, interventionLine($0, bundle: bundle, locale: locale), since: $0.stageSince, attention: Attention(kind: $0.needsHumanKind))
    }
    let running = snapshot.epics.filter { $0.status == .running }.map {
        row(.active($0), .running, doing($0) ?? runningLine($0, bundle: bundle, locale: locale), since: $0.stageSince)
    }
    let waiting = snapshot.queue.enumerated().map {
        row(.queued($1, position: $0 + 1), .waiting, Copy.sidebarWaitingForSlot(bundle: bundle, locale: locale), since: $1.queuedAt)
    }
    let ready = snapshot.done.map {
        row(.finished($0), .ready, $0.prNumber.map { Copy.sidebarPr(number: String($0), bundle: bundle, locale: locale) } ?? Copy.sidebarReadyForTest(bundle: bundle, locale: locale), since: $0.finishedAt)
    }

    switch groupBy {
    case .status:
        let hiddenWhenEmpty = [
            SidebarGroup(title: Copy.sidebarGroupReadyForTest(bundle: bundle, locale: locale), rows: ready),
            SidebarGroup(title: Copy.sidebarGroupDone(bundle: bundle, locale: locale), rows: finished(.merged), startsCollapsed: true),
            SidebarGroup(title: Copy.sidebarGroupCancelled(bundle: bundle, locale: locale), rows: finished(.cancelled), startsCollapsed: true),
        ].filter { $0.rows.isEmpty == false }
        return [
            SidebarGroup(title: Copy.sidebarGroupNeedsAttention(bundle: bundle, locale: locale), rows: needsYou),
            SidebarGroup(title: Copy.sidebarRunning(bundle: bundle, locale: locale), rows: running),
            SidebarGroup(title: Copy.sidebarGroupUpNext(bundle: bundle, locale: locale), rows: waiting),
        ] + hiddenWhenEmpty
    case .repo:
        let byRepo = Dictionary(grouping: needsYou + running + waiting + ready + (withFinished ? finished(.merged) + finished(.cancelled) : []), by: \.repo)
        return byRepo.keys.sorted { (shortName($0).lowercased(), $0) < (shortName($1).lowercased(), $1) }.map { repo in
            SidebarGroup(title: shortName(repo), rows: byRepo[repo]!.sorted { $0.issue < $1.issue })
        }
    }
}

/// The Carrier section's state, from what the app knows of the engine (docs/specs/sidebar-home-sessions-carrier.md).
public struct CarrierCardState: Equatable {
    public enum Kind: Equatable { case running, idle, paused, stopped, problem, connecting }

    public var kind: Kind
    /// Busy and total: present for running, paused and problem (when the engine answered), and for a stopped engine from the last
    /// total it reported (nothing busy); absent otherwise.
    public var slots: (busy: Int, total: Int)?

    /// The word of the pill.
    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch kind {
        case .running: Copy.sidebarRunning(bundle: bundle, locale: locale)
        case .idle: Copy.sidebarIdle(bundle: bundle, locale: locale)
        case .paused: Copy.sidebarPaused(bundle: bundle, locale: locale)
        case .stopped: Copy.sidebarStopped(bundle: bundle, locale: locale)
        case .problem: Copy.sidebarProblem(bundle: bundle, locale: locale)
        case .connecting: Copy.sidebarConnecting(bundle: bundle, locale: locale)
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.slots?.busy == rhs.slots?.busy && lhs.slots?.total == rhs.slots?.total
    }
}

/// A problem reported by the snapshot wins over a pause: it is what the person has to look at. An engine that answers with no slot busy is
/// idle, and only one working an epic is running.
public func carrierCardState(_ state: ConnectionState?, lastTotal: Int? = nil) -> CarrierCardState {
    switch state {
    case .running(let snapshot)?:
        let kind: CarrierCardState.Kind = snapshot.problem != nil ? .problem : snapshot.paused ? .paused : snapshot.slots.busy > 0 ? .running : .idle
        return CarrierCardState(kind: kind, slots: (snapshot.slots.busy, snapshot.slots.total))
    case .incompatible?: return CarrierCardState(kind: .problem, slots: nil)
    case .stopped?: return CarrierCardState(kind: .stopped, slots: lastTotal.map { (0, $0) })
    case nil: return CarrierCardState(kind: .connecting, slots: nil)
    }
}

private func key(_ repo: String, _ issue: Int) -> String { "\(repo)#\(issue)" }

private func shortName(_ repo: String) -> String { repo.split(separator: "/").last.map(String.init) ?? repo }

func runningLine(_ epic: PanelEpic, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    let stage = switch epic.stage {
    case .ship?: Copy.sidebarStageShip(bundle: bundle, locale: locale)
    case .review?: Copy.sidebarStageReview(bundle: bundle, locale: locale)
    case .fix?: Copy.sidebarStageFix(bundle: bundle, locale: locale)
    case nil: Copy.sidebarStageStarting(bundle: bundle, locale: locale)
    }
    if let round = epic.round { return Copy.sidebarStageRound(stage: stage, round: round, max: epic.maxReviews, bundle: bundle, locale: locale) }
    if let slices = epic.slices, slices.total > 0 { return Copy.sidebarStageSlices(stage: stage, done: slices.done, total: slices.total, bundle: bundle, locale: locale) }
    return stage
}

/// Lower case, as the sidebar's detail line; Your turn capitalises it.
func interventionLine(_ epic: PanelEpic, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    switch epic.needsHumanKind {
    case "review_limit": Copy.sidebarNeedReviewLimit(bundle: bundle, locale: locale)
    case "agent_needs_human": Copy.sidebarNeedAgentNeedsHuman(bundle: bundle, locale: locale)
    case "retries_exhausted": Copy.sidebarNeedRetriesExhausted(bundle: bundle, locale: locale)
    case "timeout": Copy.sidebarNeedTimeout(bundle: bundle, locale: locale)
    case "auth": Copy.sidebarNeedAuth(bundle: bundle, locale: locale)
    case "workspace": Copy.sidebarNeedWorkspace(bundle: bundle, locale: locale)
    case "pr_invalid": Copy.sidebarNeedPrInvalid(bundle: bundle, locale: locale)
    case "skill_missing": Copy.sidebarNeedSkillMissing(bundle: bundle, locale: locale)
    case "reviewers_failed": Copy.sidebarNeedReviewersFailed(bundle: bundle, locale: locale)
    case "lead_limit": Copy.sidebarNeedLeadLimit(bundle: bundle, locale: locale)
    default: epic.shownNeedsHumanReason(bundle: bundle, locale: locale) ?? Copy.sidebarNeedYou(bundle: bundle, locale: locale)
    }
}
