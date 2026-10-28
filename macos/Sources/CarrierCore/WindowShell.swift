import Observation

// What the window's shell holds apart from Carrier's data: what is selected and which side columns are shown
// (docs/specs/macos-app-redesign.md, story 10). The views bind to it; nothing here touches AppKit or SwiftUI.

/// What the sidebar can select.
public enum Selection: Hashable {
    case home
    case sessions
    case session(id: String)
    /// The draft of a session that does not exist yet.
    case newSession
    case archive
    case carrier
    case epic(repo: String, issue: Int)
    case settings
}

/// Which of the Sessions section and the Carrier card is unfolded; the other shows its summary.
public enum OpenSection: String { case sessions, carrier }

/// The modifier keys a shortcut can carry; only ⌘ alone makes one.
public struct ShortcutModifiers: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = ShortcutModifiers(rawValue: 1)
    public static let shift = ShortcutModifiers(rawValue: 2)
    public static let option = ShortcutModifiers(rawValue: 4)
    public static let control = ShortcutModifiers(rawValue: 8)
}

/// What a shortcut asks of the window.
public enum ShortcutAction: Equatable {
    case select(Selection)
    /// Search the section that is open.
    case search
}

/// ⌘1 Home, ⌘2 the Sessions home, ⌘3 the Carrier home, ⌘N the new session's draft, ⌘F the search of the open section; anything else, or these keys with another
/// modifier, is nothing. `key` is the character without modifiers.
public func shortcutAction(key: String, modifiers: ShortcutModifiers) -> ShortcutAction? {
    guard modifiers == .command else { return nil }
    switch key.lowercased() {
    case "1": return .select(.home)
    case "2": return .select(.sessions)
    case "3": return .select(.carrier)
    case "n": return .select(.newSession)
    case "f": return .search
    default: return nil
    }
}

/// A request to open the search of a section; `count` makes asking twice a change the views can see.
public struct SearchRequest: Equatable {
    public let section: OpenSection
    public let count: Int
}

@Observable public final class WindowShell {
    /// Choosing a session or the Sessions home opens Sessions, an epic or the Carrier home opens the card; the rest leave it.
    public var selection: Selection = .home {
        didSet {
            switch selection {
            case .sessions, .session, .newSession: open = .sessions
            case .carrier, .epic: open = .carrier
            case .home, .archive, .settings: break
            }
        }
    }
    /// The unfolded section; nil when both are folded.
    public var open: OpenSection?
    public var sidebarShown = true
    public var inspectorShown = true
    /// The About sheet is over the window; the selection underneath stays.
    public var aboutShown = false
    /// The last ⌘F, for the open section's search to show itself.
    public private(set) var searchRequest: SearchRequest?

    public init(open: OpenSection? = .sessions) { self.open = open }

    public func toggleSidebar() { sidebarShown.toggle() }
    public func toggleInspector() { inspectorShown.toggle() }
    public func showAbout() { aboutShown = true }

    /// Runs a shortcut: a selection as a click on it would, ⌘F as a request to the open section (nothing with both folded).
    public func perform(_ action: ShortcutAction) {
        switch action {
        case .select(let next): selection = next
        case .search:
            if let open { searchRequest = SearchRequest(section: open, count: (searchRequest?.count ?? 0) + 1) }
        }
    }

    /// Escape and a click outside close the sheet; a click on it does not.
    public func aboutInput(_ input: AboutInput) {
        if input != .clickInside { aboutShown = false }
    }

    /// Back to how a freshly opened window starts.
    public func reset(open: OpenSection? = .sessions) {
        selection = .home
        self.open = open
        sidebarShown = true
        inspectorShown = true
        aboutShown = false
        searchRequest = nil
    }
}
