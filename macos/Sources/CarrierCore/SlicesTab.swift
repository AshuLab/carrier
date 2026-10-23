import Foundation

// The Slices tab as plain values: the ring's arcs, the legend, the list of the selected group and the empty state that stands in
// for the list when only the counts are known (docs/specs/macos-app-redesign.md, story 27). The views map them one to one.

public enum SliceGroup: CaseIterable, Hashable {
    case merged, inProgress, pending

    public var title: String {
        switch self {
        case .merged: "Merged"
        case .inProgress: "In progress"
        case .pending: "Pending"
        }
    }
}

/// Which slices the list shows: all of them (Total) or one group, one at a time.
public enum SliceFilter: Equatable {
    case all
    case only(SliceGroup)
}

public struct SliceRow: Equatable {
    public var number: Int
    public var title: String
    public var state: SliceGroup
    /// In progress: the lane and the activity; pending: `ready to start` or `after #N <title>, #M <title>` (`#N` alone for a blocker not in the list); merged: its time.
    public var detail: String
    /// The slice's pull request, when the engine found one.
    public var prNumber: Int?
    /// On GitHub: the slice's issue, and its pull request when it has one. nil without the epic's repository.
    public var issueURL: String?
    public var prURL: String?
}

/// Why the list is missing while the counts are there.
public enum SlicesUnavailable: Equatable {
    /// The engine sent no `epic` reply: it shares counts only (or its first reply has not come yet).
    case notShared
    /// The engine answered with an empty list: it has not read the epic's slices from GitHub yet, or the last read failed.
    case notReadYet

    public var icon: String {
        switch self {
        case .notShared: "text.badge.xmark"
        case .notReadYet: "arrow.triangle.2.circlepath"
        }
    }

    public var title: String {
        switch self {
        case .notShared: "Slice list unavailable"
        case .notReadYet: "Reading the slices"
        }
    }

    public var line: String {
        switch self {
        case .notShared: "This Carrier shares totals only. The count above still updates."
        case .notReadYet: "Carrier has not read them from GitHub yet. They appear after its next check."
        }
    }
}

public struct SlicesLegendEntry: Equatable {
    public var group: SliceGroup
    public var count: Int
}

public struct SlicesTabModel: Equatable {
    /// Only the groups that have slices, in ring order; the view adds Total (`total`) after them.
    public var legend: [SlicesLegendEntry]
    public var selected: SliceFilter
    public var rows: [SliceRow]
    public var merged: Int
    public var total: Int
    /// Shown instead of the list when only the counts are known.
    public var unavailable: SlicesUnavailable?

    /// Nothing to show: no slices and no counts. The view shows the "No slices yet" empty state.
    public var isEmpty: Bool { total == 0 }

    /// The ring's counts in `SliceGroup.allCases` order.
    public var counts: [Int] { SliceGroup.allCases.map { group in legend.first { $0.group == group }?.count ?? 0 } }
    public var centre: String { "\(merged)/\(total)" }
    public var caption: String { merged == total && total > 0 ? "all merged" : "merged" }
}

/// Every non-skipped slice by number, filtered. A queued epic has nothing in progress: its open slices all wait. A filter whose group has no slices
/// behaves as `.all`. Without the `epic` list the snapshot's counts make the ring (merged and pending) and the list is replaced by an empty state.
public func slicesTabModel(_ subject: EpicSubject?, reply: EpicReply?, filter: SliceFilter = .all, now: Int) -> SlicesTabModel {
    let slices = (reply?.slices ?? []).filter { $0.state != "skipped" }.sorted { $0.number < $1.number }
    var rows: [SliceRow] = []
    let titles = Dictionary((reply?.slices ?? []).map { ($0.number, $0.title) }, uniquingKeysWith: { first, _ in first })
    var queued = false
    if case .queued? = subject { queued = true }
    for slice in slices {
        let (group, detail): (SliceGroup, String)
        switch slice.state {
        case "closed": (group, detail) = (.merged, slice.closedAt.map { agoLine($0, now: now) } ?? "merged")
        case "in_progress" where queued == false:
            let hints = [slice.lane.map { "lane \($0)" }, slice.activity].compactMap { $0 }
            (group, detail) = (.inProgress, hints.first.map { _ in hints.joined(separator: " · ") } ?? "working")
        default:
            (group, detail) = (.pending, slice.blockedBy.isEmpty ? "ready to start" : "after " + slice.blockedBy.map { "#\($0)" + (titles[$0].map { " \($0)" } ?? "") }.joined(separator: ", "))
        }
        let base = subject.map { "https://github.com/\($0.repo)" }
        rows.append(SliceRow(
            number: slice.number, title: slice.title, state: group, detail: detail, prNumber: slice.prNumber,
            issueURL: base.map { "\($0)/issues/\(slice.number)" }, prURL: slice.prNumber.flatMap { number in base.map { "\($0)/pull/\(number)" } }
        ))
    }

    var counts = Dictionary(uniqueKeysWithValues: SliceGroup.allCases.map { group in (group, rows.filter { $0.state == group }.count) })
    var unavailable: SlicesUnavailable?
    if slices.isEmpty, case .active(let epic)? = subject, let sliceCounts = epic.slices, sliceCounts.total > 0 {
        counts[.merged] = sliceCounts.done
        counts[.pending] = max(0, sliceCounts.total - sliceCounts.done)
        unavailable = reply == nil ? .notShared : .notReadYet
    }

    let legend = SliceGroup.allCases.compactMap { group in
        counts[group].flatMap { $0 > 0 ? SlicesLegendEntry(group: group, count: $0) : nil }
    }
    var selected = SliceFilter.all
    if case .only(let group) = filter, legend.contains(where: { $0.group == group }) { selected = filter }
    return SlicesTabModel(
        legend: legend, selected: selected, rows: rows.filter { row in selected == .all || selected == .only(row.state) },
        merged: counts[.merged] ?? 0, total: legend.reduce(0) { $0 + $1.count }, unavailable: unavailable
    )
}

// MARK: ring

/// One group's arc on the ring: where its centre line starts and ends, in turns from 12 o'clock, clockwise. A full circle has
/// no caps (`full`); every other arc is stroked with round caps, which reach `lineWidth / 2` beyond each end.
public struct RingArc: Equatable, Sendable {
    public var group: Int
    public var start: Double
    public var end: Double
    public var full: Bool
}

/// The arcs of `counts` (one per group, in order; empty groups get none) on a ring of `radius` and `lineWidth`. `gap` is the space
/// left between the caps of two neighbours, so the centre lines are `gap + lineWidth` apart and the caps never touch; an arc
/// shorter than a dot is drawn as a dot. Arcs never overlap and together never pass a full turn.
public func ringArcs(_ counts: [Int], radius: Double, lineWidth: Double, gap: Double) -> [RingArc] {
    let total = counts.reduce(0, +)
    let circumference = 2 * Double.pi * radius
    guard total > 0, circumference > 0 else { return [] }
    let present = counts.indices.filter { counts[$0] > 0 }
    if present.count == 1 { return [RingArc(group: present[0], start: 0, end: 1, full: true)] }
    let apart = gap + lineWidth
    var before = 0
    return counts.indices.compactMap { group in
        defer { before += counts[group] }
        guard counts[group] > 0 else { return nil }
        let slot = (Double(before) * circumference / Double(total), Double(before + counts[group]) * circumference / Double(total))
        let middle = (slot.0 + slot.1) / 2
        let half = max((slot.1 - slot.0 - apart) / 2, 0.05)
        return RingArc(group: group, start: (middle - half) / circumference, end: (middle + half) / circumference, full: false)
    }
}
