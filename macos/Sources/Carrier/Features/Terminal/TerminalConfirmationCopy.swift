import CarrierCore
import Foundation

/// Scope for checking or tearing down terminal panes.
enum TerminalCloseTarget: Hashable {
    case pane(UUID)
    case tab(UUID)
    case owner(TerminalOwner)
    case owners([TerminalOwner])
    case all
}

/// Summary of running non-shell commands inside one terminal pane.
struct TerminalActiveProcess: Equatable {
    let paneId: UUID
    let paneTitle: String
    let commands: [String]
}

private func clipConfirmationTitle(_ title: String?, maxLength: Int = 48) -> String? {
    guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false else {
        return nil
    }
    guard trimmed.count > maxLength else { return trimmed }
    return String(trimmed.prefix(maxLength - 1)) + "\u{2026}"
}

/// Builds consistent close confirmation copy across panes, tabs, session removals, and app quit.
func terminalConfirmationQuestion(
    for target: TerminalCloseTarget,
    running: [TerminalActiveProcess],
    targetTitle: String? = nil,
    removalKind: SessionRemovalKind? = nil,
    inspectionError: String? = nil
) -> Question {
    let count = running.count
    let primaryPaneName = clipConfirmationTitle(running.first?.paneTitle ?? targetTitle)
    let clippedTargetTitle = clipConfirmationTitle(targetTitle)
    let allCommands = Array(Set(running.flatMap(\.commands))).sorted()
    let commandSummary: String?
    let commandPronoun: String
    switch allCommands.count {
    case 0:
        commandSummary = nil
        commandPronoun = count == 1 ? "it" : "active commands"
    case 1:
        commandSummary = "A command is still running: \(allCommands[0])."
        commandPronoun = "it"
    case 2...3:
        commandSummary = "Commands still running: \(allCommands.joined(separator: ", "))."
        commandPronoun = "them"
    default:
        let shown = allCommands.prefix(3).joined(separator: ", ")
        let remaining = allCommands.count - 3
        commandSummary = "Commands still running: \(shown), and \(remaining) more."
        commandPronoun = "them"
    }

    switch target {
    case .pane:
        let title = primaryPaneName.map { "Close \u{201C}\($0)\u{201D}?" } ?? "Close terminal?"
        if let commandSummary {
            return Question(
                title: title,
                message: "\(commandSummary) Closing this terminal will terminate \(commandPronoun).",
                confirm: "Close"
            )
        }
        if inspectionError != nil {
            return Question(
                title: title,
                message: "Could not verify running commands. Closing this terminal may terminate an active command.",
                confirm: "Close"
            )
        }
        return Question(
            title: title,
            message: "A command is still running in this terminal. Closing this terminal will terminate it.",
            confirm: "Close"
        )

    case .tab:
        let tabLabel = clippedTargetTitle.map { " \u{201C}\($0)\u{201D}" } ?? ""
        let title = count <= 1
            ? "Close tab\(tabLabel)?"
            : "Close tab\(tabLabel) with \(count) running terminals?"
        if let commandSummary {
            return Question(
                title: title,
                message: "\(commandSummary) Closing this tab will terminate \(commandPronoun).",
                confirm: "Close"
            )
        }
        return Question(
            title: title,
            message: "Could not verify running commands. Closing this tab may terminate active commands.",
            confirm: "Close"
        )

    case .owner, .owners:
        let multiOwner: Bool = switch target {
        case .owners(let owners) where owners.count > 1: true
        default: false
        }
        let sessionWord = multiOwner ? "these sessions" : "this session"
        let terminalWord = count == 1 ? "its terminal" : "its terminals"
        let (titlePrefix, bodyAction, errorAction, confirmLabel): (String, String, String, String) = switch removalKind {
        case .archive:
            (
                "Archive session",
                "Archiving \(sessionWord) will close \(terminalWord) and terminate \(commandPronoun).",
                "Archiving \(sessionWord) will close \(terminalWord) and may terminate active commands.",
                "Archive"
            )
        case .delete:
            (
                "Delete session",
                "Deleting \(sessionWord) will close \(terminalWord) and terminate \(commandPronoun).",
                "Deleting \(sessionWord) will close \(terminalWord) and may terminate active commands.",
                "Delete"
            )
        case .clear:
            (
                "Delete archived sessions",
                "Deleting these sessions will close their terminals and terminate \(commandPronoun).",
                "Deleting these sessions will close their terminals and may terminate active commands.",
                "Delete all"
            )
        case .none:
            (
                "Close session terminal\(count <= 1 ? "" : "s")",
                "Closing \(terminalWord) will terminate \(commandPronoun).",
                "Closing \(terminalWord) may terminate active commands.",
                "Close"
            )
        }
        let title: String
        if removalKind == .clear {
            if count == 0 {
                title = "Delete archived sessions?"
            } else {
                title = count == 1
                    ? "Delete archived sessions with a running terminal?"
                    : "Delete archived sessions with \(count) running terminals?"
            }
        } else if count == 0 {
            title = "\(titlePrefix)?"
        } else {
            title = count == 1
                ? "\(titlePrefix) with running terminal\(primaryPaneName.map { " \u{201C}\($0)\u{201D}" } ?? "")?"
                : "\(titlePrefix) with \(count) running terminals?"
        }
        if let commandSummary {
            return Question(title: title, message: "\(commandSummary) \(bodyAction)", confirm: confirmLabel)
        }
        return Question(
            title: title,
            message: "Could not verify running commands. \(errorAction)",
            confirm: confirmLabel
        )

    case .all:
        let title: String
        if count == 0 {
            title = "Quit Carrier?"
        } else {
            title = count == 1
                ? "Quit Carrier with running terminal\(primaryPaneName.map { " \u{201C}\($0)\u{201D}" } ?? "")?"
                : "Quit Carrier with \(count) running terminals?"
        }
        if let commandSummary {
            return Question(title: title, message: "\(commandSummary) Quitting Carrier will terminate \(commandPronoun).", confirm: "Quit")
        }
        return Question(
            title: title,
            message: "Could not verify running commands. Quitting Carrier may terminate active commands.",
            confirm: "Quit"
        )
    }
}
