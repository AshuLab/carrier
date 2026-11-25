import Foundation

/// Scope for checking or tearing down terminal panes.
public enum TerminalCloseTarget: Hashable {
    case pane(UUID)
    case tab(UUID)
    case owner(TerminalOwner)
    case owners([TerminalOwner])
    case all
}

/// Summary of running non-shell commands inside one terminal pane.
public struct TerminalActiveProcess: Equatable {
    public let paneId: UUID
    public let paneTitle: String
    public let commands: [String]

    public init(paneId: UUID, paneTitle: String, commands: [String]) {
        self.paneId = paneId
        self.paneTitle = paneTitle
        self.commands = commands
    }
}

private func clipConfirmationTitle(_ title: String?, maxLength: Int = 48) -> String? {
    guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false else {
        return nil
    }
    guard trimmed.count > maxLength else { return trimmed }
    return String(trimmed.prefix(maxLength - 1)) + "\u{2026}"
}

/// Builds consistent close confirmation copy across panes, tabs, session removals, and app quit, in the language of `bundle` and `locale`.
public func terminalConfirmationQuestion(
    for target: TerminalCloseTarget,
    running: [TerminalActiveProcess],
    targetTitle: String? = nil,
    removalKind: SessionRemovalKind? = nil,
    inspectionError: String? = nil,
    bundle: Bundle? = nil,
    locale: Locale = .current
) -> Question {
    let count = running.count
    let primaryPaneName = clipConfirmationTitle(running.first?.paneTitle ?? targetTitle)
    let clippedTargetTitle = clipConfirmationTitle(targetTitle)
    let allCommands = Array(Set(running.flatMap(\.commands))).sorted()
    let commandSummary: String?
    let commandPronoun: Copy.TerminalConfirmWhat
    switch allCommands.count {
    case 0:
        commandSummary = nil
        commandPronoun = count == 1 ? .it : .other
    case 1:
        commandSummary = Copy.terminalConfirmSummaryOne(command: allCommands[0], bundle: bundle, locale: locale)
        commandPronoun = .it
    case 2...3:
        commandSummary = Copy.terminalConfirmSummaryFew(commands: allCommands.joined(separator: ", "), bundle: bundle, locale: locale)
        commandPronoun = .them
    default:
        let shown = allCommands.prefix(3).joined(separator: ", ")
        commandSummary = Copy.terminalConfirmSummaryMore(commands: shown, count: allCommands.count - 3, bundle: bundle, locale: locale)
        commandPronoun = .them
    }
    let what = Copy.terminalConfirmWhat(which: commandPronoun, bundle: bundle, locale: locale)
    let close = Copy.terminalConfirmClose(bundle: bundle, locale: locale)

    switch target {
    case .pane:
        let title = primaryPaneName.map { Copy.terminalConfirmPaneTitleNamed(name: $0, bundle: bundle, locale: locale) }
            ?? Copy.terminalConfirmPaneTitle(bundle: bundle, locale: locale)
        if let commandSummary {
            return Question(
                title: title,
                message: Copy.terminalConfirmPaneMessage(summary: commandSummary, what: what, bundle: bundle, locale: locale),
                confirm: close
            )
        }
        if inspectionError != nil {
            return Question(title: title, message: Copy.terminalConfirmPaneUnverified(bundle: bundle, locale: locale), confirm: close)
        }
        return Question(title: title, message: Copy.terminalConfirmPaneRunning(bundle: bundle, locale: locale), confirm: close)

    case .tab:
        let title: String
        switch (clippedTargetTitle, count <= 1) {
        case (let name?, true): title = Copy.terminalConfirmTabTitleNamed(name: name, bundle: bundle, locale: locale)
        case (nil, true): title = Copy.terminalConfirmTabTitle(bundle: bundle, locale: locale)
        case (let name?, false): title = Copy.terminalConfirmTabTitleNamedMany(count: count, name: name, bundle: bundle, locale: locale)
        case (nil, false): title = Copy.terminalConfirmTabTitleMany(count: count, bundle: bundle, locale: locale)
        }
        if let commandSummary {
            return Question(
                title: title,
                message: Copy.terminalConfirmTabMessage(summary: commandSummary, what: what, bundle: bundle, locale: locale),
                confirm: close
            )
        }
        return Question(title: title, message: Copy.terminalConfirmTabUnverified(bundle: bundle, locale: locale), confirm: close)

    case .owner, .owners:
        let multiOwner: Bool = switch target {
        case .owners(let owners) where owners.count > 1: true
        default: false
        }
        let sessions = Copy.terminalConfirmSessions(which: multiOwner ? .many : .other, bundle: bundle, locale: locale)
        let terminals = Copy.terminalConfirmTerminals(count: count, bundle: bundle, locale: locale)
        let prefixKind: Copy.TerminalConfirmOwnerPrefix
        let messageKind: Copy.TerminalConfirmOwnerMessage
        let unverifiedKind: Copy.TerminalConfirmOwnerUnverified
        let confirmKind: Copy.TerminalConfirmOwnerConfirm
        switch removalKind {
        case .archive: (prefixKind, messageKind, unverifiedKind, confirmKind) = (.archive, .archive, .archive, .archive)
        case .delete: (prefixKind, messageKind, unverifiedKind, confirmKind) = (.delete, .delete, .delete, .delete)
        case .clear: (prefixKind, messageKind, unverifiedKind, confirmKind) = (.clear, .clear, .clear, .clear)
        case .none: (prefixKind, messageKind, unverifiedKind, confirmKind) = (count <= 1 ? .other : .many, .other, .other, .other)
        }
        let prefix = Copy.terminalConfirmOwnerPrefix(which: prefixKind, bundle: bundle, locale: locale)
        let title: String
        if count == 0 {
            title = Copy.terminalConfirmOwnerTitle(prefix: prefix, bundle: bundle, locale: locale)
        } else if count == 1 {
            if removalKind == .clear {
                title = Copy.terminalConfirmOwnerTitleClearOne(bundle: bundle, locale: locale)
            } else if let primaryPaneName {
                title = Copy.terminalConfirmOwnerTitleOneNamed(prefix: prefix, name: primaryPaneName, bundle: bundle, locale: locale)
            } else {
                title = Copy.terminalConfirmOwnerTitleOne(prefix: prefix, bundle: bundle, locale: locale)
            }
        } else {
            title = Copy.terminalConfirmOwnerTitleMany(count: count, prefix: prefix, bundle: bundle, locale: locale)
        }
        let confirm = Copy.terminalConfirmOwnerConfirm(which: confirmKind, bundle: bundle, locale: locale)
        if let commandSummary {
            let action = Copy.terminalConfirmOwnerMessage(which: messageKind, sessions: sessions, terminals: terminals, what: what, bundle: bundle, locale: locale)
            return Question(
                title: title,
                message: Copy.terminalConfirmSummaryThen(summary: commandSummary, then: action, bundle: bundle, locale: locale),
                confirm: confirm
            )
        }
        let action = Copy.terminalConfirmOwnerUnverified(which: unverifiedKind, sessions: sessions, terminals: terminals, bundle: bundle, locale: locale)
        return Question(
            title: title,
            message: Copy.terminalConfirmUnverifiedThen(then: action, bundle: bundle, locale: locale),
            confirm: confirm
        )

    case .all:
        let title: String
        if count == 0 {
            title = Copy.terminalConfirmQuitTitle(bundle: bundle, locale: locale)
        } else if count == 1 {
            title = primaryPaneName.map { Copy.terminalConfirmQuitTitleOneNamed(name: $0, bundle: bundle, locale: locale) }
                ?? Copy.terminalConfirmQuitTitleOne(bundle: bundle, locale: locale)
        } else {
            title = Copy.terminalConfirmQuitTitleMany(count: count, bundle: bundle, locale: locale)
        }
        let quit = Copy.terminalConfirmQuit(bundle: bundle, locale: locale)
        if let commandSummary {
            return Question(
                title: title,
                message: Copy.terminalConfirmQuitMessage(summary: commandSummary, what: what, bundle: bundle, locale: locale),
                confirm: quit
            )
        }
        return Question(title: title, message: Copy.terminalConfirmQuitUnverified(bundle: bundle, locale: locale), confirm: quit)
    }
}
