import Foundation

// The rows of the Agent output tab as the view draws them: the transcript's items with each run of successful calls folded into
// one group (docs/specs/agent-output-quiet-log.md). A pure step over `Transcript.items`, so an append never rebuilds the transcript.

public enum FlowItem: Equatable, Identifiable {
    /// A message, note, error, skill, edit or a call that is a line of its own.
    case item(TranscriptItem)
    /// Two or more successful calls in a row; its id is the id of the first.
    case group(id: Int, calls: [TranscriptItem])
    /// A subagent, at the id of its first `task` start.
    case slice(LaneSection)

    public var id: Int {
        switch self {
        case .item(let item): item.id
        case .group(let id, _): id
        case .slice(let lane): lane.startId
        }
    }
}

/// Whether an item can be in a group: a finished, successful call that is not an edit or a skill.
private func isGroupable(_ item: TranscriptItem) -> Bool {
    guard case .tool(_, let card) = item else { return false }
    return card.status == .ok && card.kind != .edit && card.isSkill == false
}

/// A run of two or more groupable items in a row is one group; anything else, a lone call included, stays an item. A slice
/// sits before the first item with a higher id and ends a run, so a group never spans one.
public func flowItems(_ items: [TranscriptItem], slices: [LaneSection] = []) -> [FlowItem] {
    var later = slices.sorted { $0.startId < $1.startId }[...]
    var flow: [FlowItem] = []
    var run: [TranscriptItem] = []
    func close() {
        if run.count >= 2 { flow.append(.group(id: run[0].id, calls: run)) } else { flow += run.map(FlowItem.item) }
        run = []
    }
    for item in items {
        while let slice = later.first, slice.startId < item.id {
            close()
            flow.append(.slice(slice))
            later = later.dropFirst()
        }
        if isGroupable(item) { run.append(item) } else {
            close()
            flow.append(.item(item))
        }
    }
    close()
    return flow + later.map(FlowItem.slice)
}

private func cards(_ calls: [TranscriptItem]) -> [TranscriptCard] {
    calls.compactMap { if case .tool(_, let card) = $0 { card } else { nil } }
}

/// "Ran 4 commands · read 2 files": the calls counted by kind in the order of the first call, the first word capitalised, two
/// parts at most and "+N more" (N calls) after.
public func callGroupLabel(_ calls: [TranscriptItem]) -> String {
    var kinds: [ToolKind] = []
    var counts: [ToolKind: Int] = [:]
    for card in cards(calls) {
        if counts[card.kind] == nil { kinds.append(card.kind) }
        counts[card.kind, default: 0] += 1
    }
    func part(_ kind: ToolKind) -> String {
        let n = counts[kind] ?? 0
        return switch kind {
        case .shell: "Ran \(n) command\(n == 1 ? "" : "s")"
        case .read: "read \(n) file\(n == 1 ? "" : "s")"
        case .search: "searched \(n) time\(n == 1 ? "" : "s")"
        case .edit, .other: "used \(n) tool\(n == 1 ? "" : "s")"
        }
    }
    var parts = kinds.prefix(2).map(part)
    let rest = kinds.dropFirst(2).reduce(0) { $0 + (counts[$1] ?? 0) }
    if rest > 0 { parts.append("+\(rest) more") }
    let label = parts.joined(separator: " · ")
    return label.prefix(1).uppercased() + label.dropFirst()
}

/// The sum of the calls' own durations, formatted like a call's; nil when none of them has one.
public func callGroupDuration(_ calls: [TranscriptItem]) -> String? {
    let all = cards(calls).compactMap(\.durationMs)
    return all.isEmpty ? nil : formatCallDuration(all.reduce(0, +))
}

/// Which groups the user opened, by the id of their first call; a group nobody touched is folded.
public struct GroupFolds: Equatable {
    private var open: Set<Int> = []

    public init() {}

    public func isOpen(_ id: Int) -> Bool { open.contains(id) }

    public mutating func toggle(_ id: Int) {
        if open.insert(id).inserted == false { open.remove(id) }
    }
}
