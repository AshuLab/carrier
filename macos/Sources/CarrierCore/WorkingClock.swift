import Foundation

/// When each session the app has seen working started, so its row can count how long it has worked. The host does not say: a session's
/// last activity moves with every event, so the first time the app sees it working is the start, taken as that last activity (which is
/// the turn's start unless more events came first). Waiting for the person keeps the count, since the turn goes on; idle or done ends it.
@MainActor public final class WorkingClock {
    public static let shared = WorkingClock()
    private var started: [String: Date] = [:]

    public init() {}

    /// When the row's turn started, nil unless it is working. Reading it is how the clock learns a session started or stopped.
    public func since(_ row: SessionRow) -> Date? {
        switch row.state {
        case .idle, .done:
            started[row.id] = nil
            return nil
        case .waiting:
            return nil
        case .working:
            if let known = started[row.id] { return known }
            started[row.id] = row.updatedAt
            return row.updatedAt
        }
    }
}

/// How long a turn has run, with its units, in the wording of `formatDuration` but counting seconds up to an hour:
/// "42s", "12m 05s", "2h 03m", "1d 4h".
public func workingElapsed(_ seconds: Int) -> String {
    let s = max(0, seconds)
    let (d, h, m) = (s / 86_400, s % 86_400 / 3600, s % 3600 / 60)
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
    if m > 0 { return "\(m)m \(String(format: "%02d", s % 60))s" }
    return "\(s)s"
}
