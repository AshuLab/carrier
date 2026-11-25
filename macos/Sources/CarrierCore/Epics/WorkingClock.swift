import Foundation

extension SessionRow {
    /// When the turn it runs now started, nil unless it is working. It is the start `WorkingOrder` holds, which restarts with each turn (a session
    /// that waits for the person or for what it started in the background keeps the turn it had), so it does not depend on this row being on screen.
    public var workingSince: Date? {
        guard state != .waiting, isWorking else { return nil }
        return orderedAt ?? updatedAt
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
