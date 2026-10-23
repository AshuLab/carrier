import Foundation

// The epics section of the menu bar menu: plain values the AppKit menu maps one to one (docs/specs/macos-app-redesign.md, story 32).

/// The user default behind the switch in Settings; on unless set otherwise.
public let showEpicsKey = "menu.showEpics"

public enum EpicMenuState: Equatable {
    case needsYou, running, waiting, ready, done, cancelled

    /// The SF Symbol of the glyph.
    public var symbol: String {
        switch self {
        case .needsYou: "exclamationmark.circle.fill"
        case .running: "circle.dotted"
        case .waiting: "circle"
        case .ready: "checkmark.circle.fill"
        case .done: "checkmark.circle"
        case .cancelled: "xmark.circle"
        }
    }

    /// The glyph's colour, by name; the app maps it to a system colour.
    public var colorName: String {
        switch self {
        case .needsYou: "orange"
        case .running: "green"
        case .waiting: "gray"
        case .ready: "blue"
        case .done: "green"
        case .cancelled: "gray"
        }
    }
}

public struct EpicMenuItem: Equatable {
    public var repo: String
    public var issue: Int
    public var state: EpicMenuState
    /// "agent-forge #231": the repository's name, never its owner, and the number.
    public var title: String
    /// The secondary line under the title.
    public var detail: String
    /// "r/m" (review round of the maximum) or "d/t" (slices done of total); nil when there is nothing to count.
    public var badge: String?
}

public struct EpicMenu: Equatable {
    public static let limit = 20

    public var items: [EpicMenuItem]
    /// "… and 3 more" when the snapshot has more than `limit` epics.
    public var more: String?
}

/// The section for `snapshot`, or nil when the setting is off or there are no epics. Order: needs you, running, waiting, ready.
public func epicMenu(_ snapshot: PanelSnapshot, showEpics: Bool) -> EpicMenu? {
    guard showEpics else { return nil }
    func name(_ repo: String, _ issue: Int) -> String { "\(repo.split(separator: "/").last.map(String.init) ?? repo) #\(issue)" }

    let needsYou = snapshot.epics.filter { $0.status == .needsHuman }.map { epic in
        EpicMenuItem(
            repo: epic.repo, issue: epic.issue, state: .needsYou, title: name(epic.repo, epic.issue),
            detail: epic.needsHumanReason ?? "needs you", badge: slicesBadge(epic.slices)
        )
    }
    let running = snapshot.epics.filter { $0.status == .running }.map { epic in
        // after the first review the round says more than the slices do
        let inReview = epic.stage == .review || epic.stage == .fix
        let badge = inReview ? roundBadge(epic) ?? slicesBadge(epic.slices) : slicesBadge(epic.slices)
        return EpicMenuItem(
            repo: epic.repo, issue: epic.issue, state: .running, title: name(epic.repo, epic.issue),
            detail: [epic.stage?.rawValue, roundLine(epic)].compactMap { $0 }.joined(separator: " · ").nilIfEmpty ?? "starting", badge: badge
        )
    }
    let waiting = snapshot.queue.map {
        EpicMenuItem(repo: $0.repo, issue: $0.issue, state: .waiting, title: name($0.repo, $0.issue), detail: "waiting", badge: nil)
    }
    let ready = snapshot.done.map {
        EpicMenuItem(
            repo: $0.repo, issue: $0.issue, state: .ready, title: name($0.repo, $0.issue),
            detail: $0.prNumber.map { "ready for test · PR #\($0)" } ?? "ready for test", badge: nil
        )
    }

    let all = needsYou + running + waiting + ready
    guard all.isEmpty == false else { return nil }
    let hidden = all.count - EpicMenu.limit
    return EpicMenu(items: Array(all.prefix(EpicMenu.limit)), more: hidden > 0 ? "… and \(hidden) more" : nil)
}

private func roundBadge(_ epic: PanelEpic) -> String? { epic.round.map { "\($0)/\(epic.maxReviews)" } }

private func slicesBadge(_ slices: PanelEpic.Slices?) -> String? {
    guard let slices, slices.total > 0 else { return nil }
    return "\(slices.done)/\(slices.total)"
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
