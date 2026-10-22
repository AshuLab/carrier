import Foundation

// The Slices tab as plain values: the ring's arcs, the legend, the list of the selected group and the notice for an engine that
// only has counts (docs/specs/macos-app-redesign.md, story 27). The views map them one to one.

public enum SliceGroup: CaseIterable, Hashable {
    case merged, inProgress, waiting

    public var title: String {
        switch self {
        case .merged: "Merged"
        case .inProgress: "In progress"
        case .waiting: "Waiting"
        }
    }
}

public struct SliceRow: Equatable {
    public var number: Int
    public var title: String
    /// In progress: the lane and the activity; waiting: `ready to start` or `after #N`; merged: its time.
    public var detail: String
    /// The slice's pull request, when the engine found one.
    public var prNumber: Int?
    /// On GitHub: the slice's issue, and its pull request when it has one. nil without the epic's repository.
    public var issueURL: String?
    public var prURL: String?
}

public struct SlicesLegendEntry: Equatable {
    public var group: SliceGroup
    public var count: Int
}

public struct SlicesTabModel: Equatable {
    /// Only the groups that have slices, in ring order.
    public var legend: [SlicesLegendEntry]
    public var selected: SliceGroup?
    public var rows: [SliceRow]
    public var merged: Int
    public var total: Int
    /// Said instead of the list when the engine only has counts.
    public var notice: String?

    /// Nothing to show: no slices and no counts. The view shows the "No slices yet" empty state.
    public var isEmpty: Bool { total == 0 }

    /// The ring's counts in `SliceGroup.allCases` order.
    public var counts: [Int] { SliceGroup.allCases.map { group in legend.first { $0.group == group }?.count ?? 0 } }
    public var centre: String { "\(merged)/\(total)" }
    public var caption: String { merged == total && total > 0 ? "all merged" : "merged" }
}

/// A queued epic has nothing in progress: its open slices all wait. The default group is in progress, else waiting, else merged; a chosen group that is empty is ignored. Skipped slices are
/// left out. Without the `epic` list the snapshot's counts make the ring (merged and waiting) and the list is replaced by a notice.
public func slicesTabModel(_ subject: EpicSubject?, reply: EpicReply?, chosen: SliceGroup? = nil, now: Int) -> SlicesTabModel {
    let slices = (reply?.slices ?? []).filter { $0.state != "skipped" }
    var rows: [SliceGroup: [SliceRow]] = [:]
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
            (group, detail) = (.waiting, slice.blockedBy.isEmpty ? "ready to start" : "after " + slice.blockedBy.map { "#\($0)" }.joined(separator: ", "))
        }
        let base = subject.map { "https://github.com/\($0.repo)" }
        rows[group, default: []].append(SliceRow(
            number: slice.number, title: slice.title, detail: detail, prNumber: slice.prNumber,
            issueURL: base.map { "\($0)/issues/\(slice.number)" }, prURL: slice.prNumber.flatMap { number in base.map { "\($0)/pull/\(number)" } }
        ))
    }

    var counts = Dictionary(uniqueKeysWithValues: SliceGroup.allCases.map { ($0, rows[$0]?.count ?? 0) })
    var notice: String?
    if slices.isEmpty, case .active(let epic)? = subject, let sliceCounts = epic.slices, sliceCounts.total > 0 {
        counts[.merged] = sliceCounts.done
        counts[.waiting] = max(0, sliceCounts.total - sliceCounts.done)
        notice = "The list of slices is not available from this Carrier."
    }

    let legend = SliceGroup.allCases.compactMap { group in
        counts[group].flatMap { $0 > 0 ? SlicesLegendEntry(group: group, count: $0) : nil }
    }
    let present = Set(legend.map(\.group))
    let selected = [chosen, .inProgress, .waiting, .merged].lazy.compactMap { $0 }.first { present.contains($0) }
    return SlicesTabModel(
        legend: legend, selected: selected, rows: selected.flatMap { rows[$0] } ?? [],
        merged: counts[.merged] ?? 0, total: legend.reduce(0) { $0 + $1.count }, notice: notice
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
