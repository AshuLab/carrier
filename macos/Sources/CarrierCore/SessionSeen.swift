import Foundation

/// When the person last saw each session, so a session that answered since is `unread`. The host does not know what the person looked at:
/// the app keeps, per session, the last activity it had seen, in user defaults. A session met for the first time counts as seen (an old
/// list does not all turn unread the day this arrives), and the one being looked at is seen as it moves.
public struct SessionSeen: Equatable {
    public static let key = "sessions.seen"

    /// The last activity seen, by session id, in seconds since 1970.
    private var seen: [String: Double]

    public init(seen: [String: Double] = [:]) { self.seen = seen }

    public static func stored(in defaults: UserDefaults = .standard) -> SessionSeen {
        SessionSeen(seen: defaults.dictionary(forKey: key) as? [String: Double] ?? [:])
    }

    public func store(in defaults: UserDefaults = .standard) { defaults.set(seen, forKey: Self.key) }

    /// The rows with `unread` set: an idle session whose last activity is later than the one seen. `viewing` is the session open on screen;
    /// it and the sessions met for the first time are taken as seen now. Sessions that are gone are forgotten. Returns whether what was
    /// seen changed, for the caller to store it.
    public mutating func apply(to rows: inout [SessionRow], viewing: String?) -> Bool {
        let before = seen
        let present = Set(rows.map(\.id))
        seen = seen.filter { present.contains($0.key) }
        for index in rows.indices {
            let id = rows[index].id, updated = rows[index].updatedAt.timeIntervalSince1970
            if id == viewing || seen[id] == nil { seen[id] = max(seen[id] ?? 0, updated) }
            rows[index].unread = rows[index].state == .idle && updated > (seen[id] ?? updated)
        }
        return seen != before
    }

    /// Takes the session as seen at the activity the app last read, as when the person leaves it.
    public mutating func markSeen(_ id: String, in rows: [SessionRow]) {
        guard let row = rows.first(where: { $0.id == id }) else { return }
        seen[id] = max(seen[id] ?? 0, row.updatedAt.timeIntervalSince1970)
    }
}
