import Observation

// What the window's shell holds apart from Carrier's data: what is selected and which side columns are shown
// (docs/specs/macos-app-redesign.md, story 10). The views bind to it; nothing here touches AppKit or SwiftUI.

/// What the sidebar can select.
public enum Selection: Hashable {
    case home
    case sessions
    case session(id: String)
    case archive
    case carrier
    case epic(repo: String, issue: Int)
    case settings
}

/// Which of the Sessions section and the Carrier card is unfolded; the other shows its summary.
public enum OpenSection: String { case sessions, carrier }

@Observable public final class WindowShell {
    /// Choosing a session or the Sessions home opens Sessions, an epic or the Carrier home opens the card; the rest leave it.
    public var selection: Selection = .home {
        didSet {
            switch selection {
            case .sessions, .session: open = .sessions
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

    public init(open: OpenSection? = .sessions) { self.open = open }

    public func toggleSidebar() { sidebarShown.toggle() }
    public func toggleInspector() { inspectorShown.toggle() }
    public func showAbout() { aboutShown = true }

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
    }
}
