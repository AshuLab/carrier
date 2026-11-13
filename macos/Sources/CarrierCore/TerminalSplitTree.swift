import Foundation

/// Direction along which one split container divides its two children.
public enum SplitAxis: String, Codable, Sendable {
    /// Side by side (first on leading edge, second on trailing edge).
    case horizontal
    /// Stacked (first on top, second on bottom).
    case vertical
}

/// Target edge when splitting an existing pane or moving a pane next to another.
public enum SplitEdge: String, CaseIterable, Codable, Sendable {
    case leading, trailing, top, bottom

    public var axis: SplitAxis {
        switch self {
        case .leading, .trailing: .horizontal
        case .top, .bottom: .vertical
        }
    }

    public var placesTargetFirst: Bool {
        switch self {
        case .trailing, .bottom: true
        case .leading, .top: false
        }
    }
}

/// Child selector inside a `.split` node of `SplitNode`.
public enum SplitBranch: String, Codable, Sendable {
    case first
    case second
}

/// Binary layout tree inside one `TerminalTab`: every leaf holds a unique `TerminalPane.id`.
public indirect enum SplitNode: Equatable, Codable, Sendable {
    case leaf(UUID)
    case split(axis: SplitAxis, ratio: Double, first: SplitNode, second: SplitNode)

    public static let minRatio: Double = 0.15
    public static let maxRatio: Double = 0.85

    public static func clampRatio(_ ratio: Double) -> Double {
        guard ratio.isFinite else { return 0.5 }
        return min(max(ratio, minRatio), maxRatio)
    }

    /// Leaves in deterministic depth-first visual traversal order (leading/top before trailing/bottom).
    public var leafPaneIds: [UUID] {
        switch self {
        case .leaf(let id):
            return [id]
        case .split(_, _, let first, let second):
            return first.leafPaneIds + second.leafPaneIds
        }
    }

    public func contains(_ paneId: UUID) -> Bool {
        switch self {
        case .leaf(let id): id == paneId
        case .split(_, _, let first, let second): first.contains(paneId) || second.contains(paneId)
        }
    }

    /// Path of `.first` / `.second` branches leading from root to `paneId`, if present.
    public func path(to paneId: UUID) -> [SplitBranch]? {
        switch self {
        case .leaf(let id):
            return id == paneId ? [] : nil
        case .split(_, _, let first, let second):
            if let sub = first.path(to: paneId) { return [.first] + sub }
            if let sub = second.path(to: paneId) { return [.second] + sub }
            return nil
        }
    }

    /// Nearest sibling leaf to focus when `paneId` closes.
    public func sibling(of paneId: UUID) -> UUID? {
        switch self {
        case .leaf:
            return nil
        case .split(_, _, let first, let second):
            if first == .leaf(paneId) { return second.leafPaneIds.first }
            if second == .leaf(paneId) { return first.leafPaneIds.last }
            if let found = first.sibling(of: paneId) { return found }
            if let found = second.sibling(of: paneId) { return found }
            if first.contains(paneId) { return second.leafPaneIds.first }
            if second.contains(paneId) { return first.leafPaneIds.last }
            return nil
        }
    }

    /// Inserts `newPaneId` beside `targetPaneId` along `edge`, returning `nil` if `newPaneId` already exists or `targetPaneId` is missing.
    public func inserting(
        _ newPaneId: UUID,
        nextTo targetPaneId: UUID,
        edge: SplitEdge,
        ratio: Double = 0.5
    ) -> SplitNode? {
        guard newPaneId != targetPaneId, contains(newPaneId) == false, contains(targetPaneId) else {
            return nil
        }
        return replacingLeaf(targetPaneId) {
            let clamped = Self.clampRatio(ratio)
            if edge.placesTargetFirst {
                return .split(axis: edge.axis, ratio: clamped, first: .leaf(targetPaneId), second: .leaf(newPaneId))
            } else {
                return .split(axis: edge.axis, ratio: clamped, first: .leaf(newPaneId), second: .leaf(targetPaneId))
            }
        }
    }

    /// Removes `paneId` and promotes its sibling branch; returns `nil` when removing the sole root leaf.
    public func removing(_ paneId: UUID) -> (node: SplitNode?, removed: Bool) {
        switch self {
        case .leaf(let id):
            return id == paneId ? (nil, true) : (self, false)
        case .split(let axis, let ratio, let first, let second):
            let left = first.removing(paneId)
            if left.removed {
                guard let promotedLeft = left.node else { return (second, true) }
                return (.split(axis: axis, ratio: Self.clampRatio(ratio), first: promotedLeft, second: second), true)
            }
            let right = second.removing(paneId)
            if right.removed {
                guard let promotedRight = right.node else { return (first, true) }
                return (.split(axis: axis, ratio: Self.clampRatio(ratio), first: first, second: promotedRight), true)
            }
            return (self, false)
        }
    }

    /// Updates the split ratio at `path` (clamped to `[0.15, 0.85]`).
    public func settingRatio(at path: [SplitBranch], ratio: Double) -> SplitNode {
        switch self {
        case .leaf:
            return self
        case .split(let axis, let currentRatio, let first, let second):
            if path.isEmpty {
                return .split(axis: axis, ratio: Self.clampRatio(ratio), first: first, second: second)
            }
            let head = path[0]
            let tail = Array(path.dropFirst())
            switch head {
            case .first:
                return .split(axis: axis, ratio: Self.clampRatio(currentRatio), first: first.settingRatio(at: tail, ratio: ratio), second: second)
            case .second:
                return .split(axis: axis, ratio: Self.clampRatio(currentRatio), first: first, second: second.settingRatio(at: tail, ratio: ratio))
            }
        }
    }

    /// Resets every split ratio in this subtree to `0.5`.
    public func equalized() -> SplitNode {
        switch self {
        case .leaf:
            return self
        case .split(let axis, _, let first, let second):
            return .split(axis: axis, ratio: 0.5, first: first.equalized(), second: second.equalized())
        }
    }

    /// Normalizes all ratios and drops duplicate or dangling leaf references against `validPaneIds`.
    public func normalized(validPaneIds: Set<UUID>) -> SplitNode? {
        var seen: Set<UUID> = []
        return normalizedUnique(validPaneIds: validPaneIds, seen: &seen)
    }

    public func swapping(_ firstId: UUID, _ secondId: UUID) -> SplitNode {
        guard firstId != secondId else { return self }
        switch self {
        case .leaf(let id):
            if id == firstId { return .leaf(secondId) }
            if id == secondId { return .leaf(firstId) }
            return self
        case .split(let axis, let ratio, let first, let second):
            return .split(
                axis: axis,
                ratio: Self.clampRatio(ratio),
                first: first.swapping(firstId, secondId),
                second: second.swapping(firstId, secondId)
            )
        }
    }

    private func replacingLeaf(_ targetId: UUID, make: () -> SplitNode) -> SplitNode {
        switch self {
        case .leaf(let id):
            return id == targetId ? make() : self
        case .split(let axis, let ratio, let first, let second):
            return .split(
                axis: axis,
                ratio: Self.clampRatio(ratio),
                first: first.replacingLeaf(targetId, make: make),
                second: second.replacingLeaf(targetId, make: make)
            )
        }
    }

    private func normalizedUnique(validPaneIds: Set<UUID>, seen: inout Set<UUID>) -> SplitNode? {
        switch self {
        case .leaf(let id):
            guard validPaneIds.contains(id), seen.insert(id).inserted else { return nil }
            return self
        case .split(let axis, let ratio, let first, let second):
            let cleanFirst = first.normalizedUnique(validPaneIds: validPaneIds, seen: &seen)
            let cleanSecond = second.normalizedUnique(validPaneIds: validPaneIds, seen: &seen)
            switch (cleanFirst, cleanSecond) {
            case (.some(let l), .some(let r)):
                return .split(axis: axis, ratio: Self.clampRatio(ratio), first: l, second: r)
            case (.some(let only), nil), (nil, .some(let only)):
                return only
            case (nil, nil):
                return nil
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind, paneId, axis, ratio, first, second
    }

    private enum Kind: String, Codable {
        case leaf, split
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .leaf:
            self = .leaf(try container.decode(UUID.self, forKey: .paneId))
        case .split:
            self = .split(
                axis: try container.decode(SplitAxis.self, forKey: .axis),
                ratio: Self.clampRatio(try container.decode(Double.self, forKey: .ratio)),
                first: try container.decode(SplitNode.self, forKey: .first),
                second: try container.decode(SplitNode.self, forKey: .second)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .leaf(let paneId):
            try container.encode(Kind.leaf, forKey: .kind)
            try container.encode(paneId, forKey: .paneId)
        case .split(let axis, let ratio, let first, let second):
            try container.encode(Kind.split, forKey: .kind)
            try container.encode(axis, forKey: .axis)
            try container.encode(Self.clampRatio(ratio), forKey: .ratio)
            try container.encode(first, forKey: .first)
            try container.encode(second, forKey: .second)
        }
    }
}
