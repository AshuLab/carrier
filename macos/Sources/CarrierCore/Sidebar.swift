import Foundation

// The sidebar's content as plain values: the groups, their rows and detail lines, the pill and the remembered grouping
// (docs/specs/macos-app-redesign.md, stories 11 and 12). The views map them one to one.

public enum GroupBy: String, CaseIterable {
    case status, repo
}

/// The grouping choice, kept in user defaults so it survives a relaunch.
public struct SidebarStore {
    private let defaults: UserDefaults
    private let key = "sidebar.groupBy"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var groupBy: GroupBy {
        get { defaults.string(forKey: key).flatMap(GroupBy.init(rawValue:)) ?? .status }
        nonmutating set { defaults.set(newValue.rawValue, forKey: key) }
    }
}

public struct SidebarRow: Equatable {
    public var repo: String
    public var issue: Int
    public var state: EpicMenuState
    /// The repository's name, never its owner.
    public var name: String
    /// Under the name: the stage and round or slices, the kind of intervention, "waiting for a slot" or how long ago.
    public var detail: String
    /// Shown on hover: the epic's title, or "name #issue" while the engine has none.
    public var tooltip: String

    public var selection: Selection { .epic(repo: repo, issue: issue) }
}

public struct SidebarGroup: Equatable {
    public var title: String
    public var rows: [SidebarRow]
    /// Whether the group is collapsed until the user opens it. No group says it yet.
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

    public mutating func toggle(_ group: SidebarGroup, by groupBy: GroupBy) {
        chosen[Self.key(group, groupBy)] = !isCollapsed(group, by: groupBy)
    }

    private static func key(_ group: SidebarGroup, _ groupBy: GroupBy) -> String { "\(groupBy.rawValue)/\(group.title)" }
}

/// The groups for `snapshot`. By status: needs you, running, up next, ready for test (hidden when empty), rows in the
/// snapshot's order. By repository: sections ordered by name, rows by issue number.
public func sidebarGroups(_ snapshot: PanelSnapshot, by groupBy: GroupBy) -> [SidebarGroup] {
    let titles = Dictionary(
        uniqueKeysWithValues: (snapshot.epics.map { (key($0.repo, $0.issue), $0.title) } + snapshot.queue.map { (key($0.repo, $0.issue), $0.title) })
    )
    func row(_ repo: String, _ issue: Int, _ state: EpicMenuState, _ detail: String) -> SidebarRow {
        let name = shortName(repo)
        let title = titles[key(repo, issue)].flatMap { $0 }
        return SidebarRow(
            repo: repo, issue: issue, state: state, name: name, detail: detail,
            tooltip: title.flatMap { $0.isEmpty ? nil : $0 } ?? "\(name) #\(issue)"
        )
    }

    let needsYou = snapshot.epics.filter { $0.status == .needsHuman }.map { row($0.repo, $0.issue, .needsYou, interventionLine($0)) }
    let running = snapshot.epics.filter { $0.status == .running }.map { row($0.repo, $0.issue, .running, runningLine($0)) }
    let waiting = snapshot.queue.map { row($0.repo, $0.issue, .waiting, "waiting for a slot") }
    let ready = snapshot.done.map { row($0.repo, $0.issue, .ready, agoLine($0.finishedAt, now: snapshot.now)) }

    switch groupBy {
    case .status:
        let groups = [
            SidebarGroup(title: "Needs you", rows: needsYou), SidebarGroup(title: "Running", rows: running),
            SidebarGroup(title: "Up next", rows: waiting),
        ]
        return ready.isEmpty ? groups : groups + [SidebarGroup(title: "Ready for test", rows: ready)]
    case .repo:
        let byRepo = Dictionary(grouping: needsYou + running + waiting + ready, by: \.repo)
        return byRepo.keys.sorted { (shortName($0).lowercased(), $0) < (shortName($1).lowercased(), $1) }.map { repo in
            SidebarGroup(title: shortName(repo), rows: byRepo[repo]!.sorted { $0.issue < $1.issue })
        }
    }
}

public enum PillTone: Equatable {
    case green, orange, gray
}

public struct SidebarPill: Equatable {
    public var text: String
    public var tone: PillTone
}

/// Epics in use of the maximum: grey at zero, orange when every slot is busy and an epic waits, green otherwise.
public func sidebarPill(_ snapshot: PanelSnapshot) -> SidebarPill {
    let (busy, total) = (snapshot.slots.busy, snapshot.slots.total)
    let tone: PillTone = busy == 0 ? .gray : busy >= total && snapshot.queue.isEmpty == false ? .orange : .green
    return SidebarPill(text: "\(busy)/\(total)", tone: tone)
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
