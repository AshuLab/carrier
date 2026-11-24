// Where the global shortcut dictates (docs/specs/global-dictation.md, story 8): into the message box of the session in front, or into the widget.

/// What is in front when the shortcut is pressed.
public enum DictationFront: Equatable, Sendable {
    /// A session of Carrier with a message box.
    case session
    /// The draft of a new session, before it starts: its message box is the one the person is standing in.
    case draft
    case epic
    /// The Settings sheet, over whatever is selected.
    case settings
    /// Any other view of Carrier: Home, a terminal, Archive, Usage, an archived session with no box.
    case otherView
    /// Another app, or a window of Carrier that is not the main one.
    case otherApp
}

public enum DictationRoute: Equatable, Sendable { case messageBox, widget }

/// What is in front, from what the app knows: whether one of Carrier's windows is the one in front, whether that one is the Settings window,
/// what the sidebar selects and whether the open session has a message box (an archived one does not).
public func dictationFront(carrierIsFront: Bool, settingsShown: Bool, selection: Selection, sessionHasBox: Bool) -> DictationFront {
    guard carrierIsFront else { return .otherApp }
    guard settingsShown == false else { return .settings }
    switch selection {
    case .session: return sessionHasBox ? .session : .otherView
    case .newSession: return .draft
    case .epic: return .epic
    default: return .otherView
    }
}

/// Only the message box of a session, or of the draft of a new one, takes the dictation itself; everywhere else the widget does.
public func dictationRoute(for front: DictationFront) -> DictationRoute { front == .session || front == .draft ? .messageBox : .widget }
