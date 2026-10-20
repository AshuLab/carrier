/// What the menu bar icon draws, derived from the connection and the snapshot.
public struct IconState: Equatable {
    public var connected: Bool   // false when Carrier is stopped or an incompatible version
    public var working: Int      // epics with status running
    public var done: Int         // slices closed across the running epics whose slices are known
    public var total: Int        // slices across those same epics
    public var attention: Int    // epics needing a person, plus 1 when the snapshot has a problem

    public init(connected: Bool = false, working: Int = 0, done: Int = 0, total: Int = 0, attention: Int = 0) {
        self.connected = connected
        self.working = working
        self.done = done
        self.total = total
        self.attention = attention
    }

    public init(_ state: ConnectionState) {
        guard case .running(let snapshot) = state else {
            self.init()
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
            attention: snapshot.epics.filter { $0.status == .needsHuman }.count + (snapshot.problem == nil ? 0 : 1)
        )
    }

    /// How much of the bar is filled, 0 to 1.
    public var fraction: Double { total > 0 ? min(1, Double(done) / Double(total)) : 0 }

    /// Length in points of the segment that bounces over the unfilled part of the bar.
    public static let segmentLength = 4.0

    /// How far the segment can travel in a bar `trackWidth` points wide, or nil when it should not move: not working, or
    /// the unfilled part is no longer than the segment.
    public func segmentTravel(trackWidth: Double) -> Double? {
        let room = trackWidth - trackWidth * fraction
        guard connected, working > 0, room > Self.segmentLength else { return nil }
        return room - Self.segmentLength
    }
}
