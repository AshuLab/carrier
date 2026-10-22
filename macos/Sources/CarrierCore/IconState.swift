/// What the icon shows, chosen in Settings (story 33).
public enum IconStyle: String, CaseIterable {
    case countAndBar, countOnly, barOnly

    public var title: String {
        switch self {
        case .countAndBar: "Count and bar"
        case .countOnly: "Count only"
        case .barOnly: "Bar only"
        }
    }
}

/// Which parts of the icon are drawn.
public struct IconParts: Equatable {
    public var count: Bool
    public var bar: Bool
    public var dot: Bool
}

/// What the menu bar icon draws, derived from the connection and the snapshot.
public struct IconState: Equatable {
    public var connected: Bool   // false when Carrier is stopped or an incompatible version
    public var working: Int      // epics with status running
    public var done: Int         // slices closed across the running epics whose slices are known
    public var total: Int        // slices across those same epics
    public var attention: Int    // epics needing a person, plus 1 when the snapshot has a problem
    public var style: IconStyle
    public var animates: Bool    // whether the segment may bounce

    public init(
        connected: Bool = false, working: Int = 0, done: Int = 0, total: Int = 0, attention: Int = 0,
        style: IconStyle = .countAndBar, animates: Bool = true
    ) {
        self.connected = connected
        self.working = working
        self.done = done
        self.total = total
        self.attention = attention
        self.style = style
        self.animates = animates
    }

    /// The count is drawn while epics run. The bar is drawn when the style has it, and also when the style is count only but
    /// there is no count to show, so the icon never disappears from the menu bar.
    public var parts: IconParts {
        let count = style != .barOnly && connected && working > 0
        return IconParts(count: count, bar: style != .countOnly || !count, dot: attention > 0)
    }

    public init(_ state: ConnectionState, style: IconStyle = .countAndBar, animates: Bool = true) {
        guard case .running(let snapshot) = state else {
            self.init(style: style, animates: animates)
            return
        }
        let running = snapshot.epics.filter { $0.status == .running }
        // a running epic with unknown slices, or none, counts as working but stays out of the bar
        let known = running.compactMap(\.slices).filter { $0.total > 0 }
        self.init(
            connected: true,
            working: running.count,
            done: known.reduce(0) { $0 + $1.done },
            total: known.reduce(0) { $0 + $1.total },
            attention: snapshot.epics.filter { $0.status == .needsHuman }.count + (snapshot.problem == nil ? 0 : 1),
            style: style, animates: animates
        )
    }

    /// How much of the bar is filled, 0 to 1.
    public var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }

    /// Length in points of the segment that bounces over the unfilled part of the bar.
    public static let segmentLength = 4.0

    /// How far the segment can travel in a bar `trackWidth` points wide, or nil when it should not move: not working, the animation is
    /// off, the bar is hidden, or the unfilled part is no longer than the segment.
    public func segmentTravel(trackWidth: Double) -> Double? {
        let room = trackWidth - trackWidth * fraction
        guard animates, parts.bar, connected, working > 0, room > Self.segmentLength else { return nil }
        return room - Self.segmentLength
    }
}
