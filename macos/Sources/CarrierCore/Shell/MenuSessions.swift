import Foundation

/// The sessions the status menu lists: the ones that wait for the person first, then the others by how recently they moved; an archived one
/// never. `shown` fills the menu, and `more` (at most `moreLimit`) is what the "More sessions" submenu holds.
public func menuSessions(_ rows: [SessionRow], limit: Int = 4, moreLimit: Int = 12) -> (shown: [SessionRow], more: [SessionRow]) {
    let live = rows.filter { $0.archived == false }.sorted { $0.sortedAt > $1.sortedAt }
    let ordered = live.filter { $0.status == .needsYou } + live.filter { $0.status != .needsYou }
    return (Array(ordered.prefix(limit)), Array(ordered.dropFirst(limit).prefix(moreLimit)))
}
