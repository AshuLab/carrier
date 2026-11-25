import Foundation

// The words the app's shell says itself, as plain values the app turns into an alert or a window (`MenuControls`, `SessionMenu`, `WindowController`),
// so a test reads them in either language without opening one.

/// What an alert says: its title, the line under it, and its buttons, the first being the default.
public struct AlertText: Equatable, Sendable {
    public let title: String
    public let message: String?
    public let buttons: [String]
}

/// The question before Carrier is stopped while epics run.
public func stopCarrierAlert(interrupting running: Int, bundle: Bundle? = nil, locale: Locale = .current) -> AlertText {
    AlertText(
        title: Copy.alertStopTitle(bundle: bundle, locale: locale), message: Copy.alertStopMessage(running: running, bundle: bundle, locale: locale),
        buttons: [Copy.epicsToolbarStopCarrier(bundle: bundle, locale: locale), Copy.alertCancel(bundle: bundle, locale: locale)])
}

/// The alert that asks for a session's new title.
public func renameSessionAlert(bundle: Bundle? = nil, locale: Locale = .current) -> AlertText {
    AlertText(
        title: Copy.alertRenameTitle(bundle: bundle, locale: locale), message: nil,
        buttons: [Copy.alertRenameButton(bundle: bundle, locale: locale), Copy.alertCancel(bundle: bundle, locale: locale)])
}

/// What an alert that asks a `Question` says: its first button, the default, does nothing, and the second is the question's own.
public func questionAlert(_ question: Question, bundle: Bundle? = nil, locale: Locale = .current) -> AlertText {
    AlertText(title: question.title, message: question.message, buttons: [Copy.alertCancel(bundle: bundle, locale: locale), question.confirm])
}

/// The alert that says Terminal is not on the Mac, when "Open in Terminal" cannot open it.
public func terminalMissingAlert(bundle: Bundle? = nil, locale: Locale = .current) -> AlertText {
    AlertText(title: Copy.alertTerminalMissing(bundle: bundle, locale: locale), message: nil, buttons: [])
}

/// The title of the main window.
public func mainWindowTitle(bundle: Bundle? = nil, locale: Locale = .current) -> String { Copy.appName(bundle: bundle, locale: locale) }
