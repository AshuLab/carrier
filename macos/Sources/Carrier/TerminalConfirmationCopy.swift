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

/// Builds consistent close confirmation copy across panes, tabs, session removals, and app quit.
func terminalConfirmationQuestion(
    for target: TerminalCloseTarget,
    running: [TerminalActiveProcess],
    targetTitle: String? = nil,
    removalKind: SessionRemovalKind? = nil,
    inspectionError: String? = nil
) -> Question {
    let count = running.count
    let primaryPaneName = running.first?.paneTitle ?? targetTitle
    let allCommands = Array(Set(running.flatMap(\.commands))).sorted()
    let commandSummary = allCommands.isEmpty
        ? nil
        : (allCommands.count == 1 ? "A command is still running: \(allCommands[0])." : "Commands still running: \(allCommands.joined(separator: ", ")).")

    switch target {
    case .pane:
        let title = primaryPaneName.map { "Close \u{201C}\($0)\u{201D}?" } ?? "Close terminal?"
        if let commandSummary {
            return Question(
                title: title,
                message: "\(commandSummary) Closing this terminal will terminate it.",
                confirm: "Close"
            )
        }
        if let inspectionError {
            return Question(
                title: title,
                message: "Could not verify running commands (\(inspectionError)). Closing this terminal may terminate an active command.",
                confirm: "Close"
            )
        }
        return Question(
            title: title,
            message: "A command is still running in this terminal. Closing this terminal will terminate it.",
            confirm: "Close"
        )

    case .tab:
        let tabLabel = targetTitle.map { " \u{201C}\($0)\u{201D}" } ?? ""
        let title = count <= 1
            ? "Close tab\(tabLabel)?"
            : "Close tab\(tabLabel) with \(count) running terminals?"
        if let commandSummary {
            return Question(
                title: title,
                message: "\(commandSummary) Closing this tab will terminate them.",
                confirm: "Close"
            )
        }
        return Question(
            title: title,
            message: "Could not verify running commands (\(inspectionError ?? "unknown error")). Closing this tab may terminate active commands.",
            confirm: "Close"
        )

    case .owner, .owners:
        let multiOwner: Bool = switch target {
        case .owners(let owners) where owners.count > 1: true
        default: false
        }
        let sessionWord = multiOwner ? "these sessions" : "this session"
        let terminalWord = count == 1 ? "its terminal" : "its terminals"
        let (titlePrefix, bodyAction, confirmLabel): (String, String, String) = switch removalKind {
        case .archive:
            ("Archive session", "Archiving \(sessionWord) will close \(terminalWord) and terminate them.", "Archive")
        case .delete:
            ("Delete session", "Deleting \(sessionWord) will close \(terminalWord) and terminate them.", "Delete")
        case .clear:
            ("Delete archived sessions", "Deleting these sessions will close their terminals and terminate them.", "Delete all")
        case .none:
            ("Close session terminal\(count <= 1 ? "" : "s")", "Closing \(terminalWord) will terminate them.", "Close")
        }
        let title: String
        if removalKind == .clear {
            title = count <= 1
                ? "Delete archived sessions with a running terminal?"
                : "Delete archived sessions with \(count) running terminals?"
        } else {
            title = count <= 1
                ? "\(titlePrefix) with running terminal\(primaryPaneName.map { " \u{201C}\($0)\u{201D}" } ?? "")?"
                : "\(titlePrefix) with \(count) running terminals?"
        }
        if let commandSummary {
            return Question(title: title, message: "\(commandSummary) \(bodyAction)", confirm: confirmLabel)
        }
        return Question(
            title: title,
            message: "Could not verify running commands (\(inspectionError ?? "unknown error")). \(bodyAction)",
            confirm: confirmLabel
        )

    case .all:
        let title = count <= 1
            ? "Quit Carrier with running terminal\(primaryPaneName.map { " \u{201C}\($0)\u{201D}" } ?? "")?"
            : "Quit Carrier with \(count) running terminals?"
        if let commandSummary {
            return Question(title: title, message: "\(commandSummary) Quitting Carrier will terminate them.", confirm: "Quit")
        }
        return Question(
            title: title,
            message: "Could not verify running commands (\(inspectionError ?? "unknown error")). Quitting Carrier may terminate active commands.",
            confirm: "Quit"
        )
    }
}
