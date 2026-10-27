import Foundation

// The sidebar's content as plain values: the groups, their rows and detail lines, the pill and the remembered grouping
// (docs/specs/macos-app-redesign.md, stories 11 and 12). The views map them one to one.

public enum GroupBy: String, CaseIterable {
    case status, repo
}

/// The grouping and Sessions sort choices, kept in user defaults so it survives a relaunch.
public struct SidebarStore {
    private let defaults: UserDefaults
    private let key = "sidebar.groupBy"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var groupBy: GroupBy {
        get { defaults.string(forKey: key).flatMap(GroupBy.init(rawValue:)) ?? .status }
        nonmutating set { defaults.set(newValue.rawValue, forKey: key) }
    }

    public var sessionSort: SessionSort {
        get { defaults.string(forKey: "sidebar.sessionSort").flatMap(SessionSort.init(rawValue:)) ?? .workspace }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "sidebar.sessionSort") }
    }

    /// The unfolded section. Both folded is stored as "none"; a value that is not a section brings back Sessions.
    public var open: OpenSection? {
        get {
            let stored = defaults.string(forKey: "sidebar.open")
            return stored == "none" ? nil : stored.flatMap(OpenSection.init(rawValue:)) ?? .sessions
        }
        nonmutating set { defaults.set(newValue?.rawValue ?? "none", forKey: "sidebar.open") }
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
    /// Shown on the right of the second line; nil when the sidebar is grouped by repository or when `title` is nil.
    public var repoLabel: String?
    /// The stage and round or slices, the kind of intervention, "waiting for a slot" or how long ago.
    public var detail: String
    /// Only for a stuck epic: decides the colour of its glyph and of `detail`.
    public var attention: Attention?
    /// Shown on hover: the epic's title (or "name #issue" while the engine has none), then `owner/name`, then the reason of a cancelled epic.
    public var tooltip: String

    public var selection: Selection { .epic(repo: repo, issue: issue) }
}

public struct SidebarGroup: Equatable {
    public var title: String
    public var rows: [SidebarRow]
    /// Whether the group is collapsed until the user opens it: Done and Cancelled.
    public var startsCollapsed = false
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
/// A non-empty `query` keeps the rows whose title, issue number (with or without `#`) or `owner/name` contain it, ignoring case, in
/// whichever groups the grouping has, and hides the groups left empty; an empty one changes nothing.
public func sidebarGroups(_ snapshot: PanelSnapshot, by groupBy: GroupBy, query: String = "") -> [SidebarGroup] {
    let groups = allSidebarGroups(snapshot, by: groupBy)
    let needle = query.trimmingCharacters(in: .whitespaces)
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

private func allSidebarGroups(_ snapshot: PanelSnapshot, by groupBy: GroupBy) -> [SidebarGroup] {
    let titles = Dictionary(
        uniqueKeysWithValues: (snapshot.epics.map { (key($0.repo, $0.issue), $0.title) } + snapshot.queue.map { (key($0.repo, $0.issue), $0.title) })
    )
    func row(_ repo: String, _ issue: Int, _ state: EpicMenuState, _ detail: String, title own: String? = nil, note: String? = nil, attention: Attention? = nil) -> SidebarRow {
        let name = shortName(repo)
        let title = (own ?? titles[key(repo, issue)].flatMap { $0 }).flatMap { $0.isEmpty ? nil : $0 }
        return SidebarRow(
            repo: repo, issue: issue, state: state, title: title, name: name, repoLabel: groupBy == .status && title != nil ? name : nil,
            detail: detail, attention: attention, tooltip: ([title ?? "\(name) #\(issue)", repo] + (note.map { [$0] } ?? [])).joined(separator: "\n")
        )
    }
    func finished(_ status: PanelSnapshot.FinishedEpic.Status) -> [SidebarRow] {
        snapshot.finished.filter { $0.status == status }.map { epic in
            let ago = agoLine(epic.finishedAt, now: snapshot.now)
            guard status == .cancelled else { return row(epic.repo, epic.issue, .done, ago, title: epic.title) }
            let reason = epic.cancelReason.flatMap { $0.isEmpty ? nil : $0 }
            return row(epic.repo, epic.issue, .cancelled, reason.map { "\(ago) · \($0)" } ?? ago, title: epic.title, note: reason)
        }
    }

    let needsYou = snapshot.epics.filter { $0.status == .needsHuman }.map { row($0.repo, $0.issue, .needsYou, interventionLine($0), attention: Attention(kind: $0.needsHumanKind)) }
    let running = snapshot.epics.filter { $0.status == .running }.map { row($0.repo, $0.issue, .running, runningLine($0)) }
    let waiting = snapshot.queue.map { row($0.repo, $0.issue, .waiting, "waiting for a slot") }
    let ready = snapshot.done.map { row($0.repo, $0.issue, .ready, agoLine($0.finishedAt, now: snapshot.now)) }

    switch groupBy {
    case .status:
        let hiddenWhenEmpty = [
            SidebarGroup(title: "Ready for test", rows: ready),
            SidebarGroup(title: "Done", rows: finished(.merged), startsCollapsed: true),
            SidebarGroup(title: "Cancelled", rows: finished(.cancelled), startsCollapsed: true),
        ].filter { $0.rows.isEmpty == false }
        return [
            SidebarGroup(title: "Needs you", rows: needsYou), SidebarGroup(title: "Running", rows: running),
            SidebarGroup(title: "Up next", rows: waiting),
        ] + hiddenWhenEmpty
    case .repo:
        let byRepo = Dictionary(grouping: needsYou + running + waiting + ready, by: \.repo)
        return byRepo.keys.sorted { (shortName($0).lowercased(), $0) < (shortName($1).lowercased(), $1) }.map { repo in
            SidebarGroup(title: shortName(repo), rows: byRepo[repo]!.sorted { $0.issue < $1.issue })
        }
    }
}

/// The Carrier card's state, from what the app knows of the engine (docs/specs/sidebar-home-sessions-carrier.md).
public struct CarrierCardState: Equatable {
    public enum Kind: Equatable { case running, paused, stopped, problem, connecting }

    public var kind: Kind
    /// Busy and total: present for running, paused and problem (when the engine answered), absent otherwise.
    public var slots: (busy: Int, total: Int)?

    /// The word of the pill.
    public var title: String {
        switch kind {
        case .running: "Running"
        case .paused: "Paused"
        case .stopped: "Stopped"
        case .problem: "Problem"
        case .connecting: "Connecting"
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.slots?.busy == rhs.slots?.busy && lhs.slots?.total == rhs.slots?.total
    }
}

/// A problem reported by the snapshot wins over a pause: it is what the person has to look at.
public func carrierCardState(_ state: ConnectionState?) -> CarrierCardState {
    switch state {
    case .running(let snapshot)?:
        let kind: CarrierCardState.Kind = snapshot.problem != nil ? .problem : snapshot.paused ? .paused : .running
        return CarrierCardState(kind: kind, slots: (snapshot.slots.busy, snapshot.slots.total))
    case .incompatible?: return CarrierCardState(kind: .problem, slots: nil)
    case .stopped?: return CarrierCardState(kind: .stopped, slots: nil)
    case nil: return CarrierCardState(kind: .connecting, slots: nil)
    }
}

/// What is waiting, for the Carrier card. Done and Cancelled are not counted.
public struct CarrierCounters: Equatable {
    public var needsYou: Int
    public var running: Int
    public var next: Int
    public var ready: Int
}

public func carrierCounters(_ snapshot: PanelSnapshot) -> CarrierCounters {
    CarrierCounters(
        needsYou: snapshot.epics.filter { $0.status == .needsHuman }.count, running: snapshot.epics.filter { $0.status == .running }.count,
        next: snapshot.queue.count, ready: snapshot.done.count
    )
}

private func key(_ repo: String, _ issue: Int) -> String { "\(repo)#\(issue)" }

private func shortName(_ repo: String) -> String { repo.split(separator: "/").last.map(String.init) ?? repo }

func runningLine(_ epic: PanelEpic) -> String {
    let stage = epic.stage?.rawValue ?? "starting"
    if let round = epic.round { return "\(stage) · round \(round)/\(epic.maxReviews)" }
    if let slices = epic.slices, slices.total > 0 { return "\(stage) · \(slices.done)/\(slices.total) slices" }
    return stage
}

/// Lower case, as the sidebar's detail line; Your turn capitalises it.
func interventionLine(_ epic: PanelEpic) -> String {
    switch epic.needsHumanKind {
    case "review_limit": "review limit reached"
    case "agent_needs_human": "the agent needs you"
    case "retries_exhausted": "retries exhausted"
    case "timeout": "timed out"
    case "auth": "authentication failed"
    case "workspace": "workspace problem"
    case "pr_invalid": "pull request invalid"
    default: epic.needsHumanReason ?? "needs you"
    }
}
