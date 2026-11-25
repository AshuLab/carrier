import Foundation

// The findings of one review round as a card in the session that raised them (the reviewer's) or answers them (the fixer's), from the
// `epic` reply's rounds (docs/ui.md, "The review findings card"). Blockers come first, then suggestions (the review's observations).
// A part the reply does not give (an id, a link, a mark) is left out of the row, never made up.

public enum FindingMark: Equatable {
    /// First time the reviewer raised it.
    case new
    /// Still open: raised again after a fix.
    case carried
    /// A later review verified it fixed.
    case fixed

    init?(_ mark: String) {
        switch mark {
        case "new": self = .new
        case "carried": self = .carried
        case "fixed": self = .fixed
        default: return nil // a value added later shows no chip
        }
    }

    public var text: String {
        switch self {
        case .new: "new"
        case .carried: "carried"
        case .fixed: "fixed"
        }
    }
}

public struct FindingRow: Equatable {
    public enum Kind: Equatable { case blocker, suggestion }

    public var kind: Kind
    /// The reviewer's stable id, shown in monospace; nil when it gave none.
    public var id: String?
    public var text: String
    /// nil for a suggestion (the engine marks blockers only) and for a mark this app does not know.
    public var mark: FindingMark?
    /// The mark came from matching titles, because the reviewer gave no ids.
    public var approximate: Bool
    /// The discussion on GitHub; nil when the reviewer gave no link.
    public var url: String?

    public var isFixed: Bool { mark == .fixed }
}

public struct FindingsCard: Equatable {
    public enum Verdict: Equatable { case ready, changesRequested }

    public var round: Int
    public var verdict: Verdict
    /// "Ready", "Changes requested".
    public var title: String
    /// "2 blockers · 1 suggestion", "1 blocker open · 1 fixed · 1 suggestion", "no findings".
    public var summary: String
    public var rows: [FindingRow]
    /// The epic's pull request, which the header links to; nil during ship, when the reply has none.
    public var prNumber: Int?
    public var prURL: String?
}

private func plural(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

private func normal(_ title: String) -> String { title.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased() }

/// The same finding in two rounds: by id when both have one, else by title (the Review tab's rule).
private func same(_ a: EpicReply.Blocker, _ b: EpicReply.Blocker) -> Bool {
    if let x = a.id, let y = b.id { return x == y }
    return normal(a.title) == normal(b.title)
}

private func row(_ blocker: EpicReply.Blocker, mark: FindingMark?, approximate: Bool) -> FindingRow {
    FindingRow(kind: .blocker, id: blocker.id, text: blocker.title, mark: mark, approximate: approximate, url: blocker.url)
}

/// "2 blockers · 1 suggestion": the open blockers (with "open" once some are fixed), the fixed ones, the suggestions.
func findingsSummary(_ rows: [FindingRow]) -> String {
    let open = rows.filter { $0.kind == .blocker && $0.isFixed == false }.count
    let fixed = rows.filter { $0.kind == .blocker && $0.isFixed }.count
    let suggestions = rows.filter { $0.kind == .suggestion }.count
    if rows.isEmpty { return "no findings" }
    var parts: [String] = []
    if open > 0 { parts.append(plural(open, "blocker") + (fixed > 0 ? " open" : "")) } else if fixed == 0 { parts.append("0 blockers") }
    if fixed > 0 { parts.append("\(fixed) fixed") }
    if suggestions > 0 { parts.append(plural(suggestions, "suggestion")) }
    return parts.joined(separator: " · ")
}

/// The findings card of the session of `stage` (`review` or `fix`) in `round`, or nil for any other stage, with no round, with no such
/// round in the reply yet (the review is still running) or with nothing to show for the fixer.
///
/// The reviewer's card is its round as the reply lists it: blockers with their marks (a blocker the round verified fixed included) and
/// the observations. The fixer's is what the round left to answer: the open blockers, each marked fixed once the next round verified it
/// (the next round lists it as fixed), or, after an approved round, its observations (the observations pass). A round number that
/// repeats, as after a requeue, is read as its latest.
public func findingsCard(_ reply: EpicReply?, stage: String, round: Int?) -> FindingsCard? {
    guard let reply, let round, stage == "review" || stage == "fix", let index = reply.rounds.lastIndex(where: { $0.round == round }) else { return nil }
    let found = reply.rounds[index]
    let later = reply.rounds.dropFirst(index + 1).first
    var rows: [FindingRow]
    if stage == "review" {
        rows = found.blockers.map { row($0, mark: FindingMark($0.mark), approximate: $0.approximate) }
    } else {
        rows = found.blockers.filter { $0.mark != "fixed" }.map { blocker in
            let verified = later?.blockers.first { $0.mark == "fixed" && same($0, blocker) }
            return row(blocker, mark: verified == nil ? FindingMark(blocker.mark) : .fixed, approximate: verified?.approximate ?? blocker.approximate)
        }
    }
    // the open ones first, a fixed one after them
    rows = rows.filter { $0.isFixed == false } + rows.filter(\.isFixed)
    rows += found.observations.map { FindingRow(kind: .suggestion, id: $0.id, text: $0.title, mark: nil, approximate: false, url: $0.url) }
    guard stage == "review" || rows.isEmpty == false else { return nil }
    let ready = found.verdict == "approved"
    return FindingsCard(
        round: round, verdict: ready ? .ready : .changesRequested, title: ready ? "Ready" : "Changes requested", summary: findingsSummary(rows), rows: rows,
        prNumber: reply.pr?.number, prURL: reply.pr?.url
    )
}
