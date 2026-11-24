import Foundation

/// One turn of a conversation as the timeline shows it: what the person asked and the start of what the agent answered.
public struct TurnMarker: Equatable, Identifiable {
    /// The id of the person's message: where the timeline scrolls to.
    public let id: String
    public let title: String
    public let preview: String
    /// The rows of the turn, the message included, to tell which turn is on screen.
    public let rowIDs: Set<String>
}

/// A conversation shorter than this does not need a way to move around it.
public let timelineMinimumTurns = 6

/// The turns of a feed, one per message of the person. Rows before the first message (there are none in practice) belong to no turn.
public func turnMarkers(in feed: [FeedRow]) -> [TurnMarker] {
    var markers: [TurnMarker] = []
    var current: (id: String, title: String, preview: String, rows: Set<String>)?
    func close() {
        if let current { markers.append(TurnMarker(id: current.id, title: current.title, preview: current.preview, rowIDs: current.rows)) }
    }
    for row in feed {
        if case .user(let id, let text) = row {
            close()
            current = (id, oneLine(text, limit: 90), "", [id])
            continue
        }
        guard current != nil else { continue }
        current?.rows.insert(row.id)
        if case .agent(_, let text, _) = row, current?.preview.isEmpty == true { current?.preview = oneLine(text, limit: 220) }
    }
    close()
    return markers
}

/// The turns that have a row among those on screen.
public func turns(showing rowIDs: Set<String>, in markers: [TurnMarker]) -> Set<String> {
    Set(markers.filter { $0.rowIDs.isDisjoint(with: rowIDs) == false }.map(\.id))
}

private func oneLine(_ text: String, limit: Int) -> String {
    let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
}
