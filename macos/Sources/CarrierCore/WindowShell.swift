import Observation

// What the window's shell holds apart from Carrier's data: what is selected and which side columns are shown
// (docs/specs/macos-app-redesign.md, story 10). The views bind to it; nothing here touches AppKit or SwiftUI.

/// What the sidebar can select.
public enum Selection: Hashable {
    case overview
    case epic(repo: String, issue: Int)
    case settings
    case about
}

@Observable public final class WindowShell {
    public var selection: Selection = .overview
    public var sidebarShown = true
    public var inspectorShown = true

    public init() {}

    public func toggleSidebar() { sidebarShown.toggle() }
    public func toggleInspector() { inspectorShown.toggle() }

    /// Back to how a freshly opened window starts.
    public func reset() {
        selection = .overview
        sidebarShown = true
        inspectorShown = true
    }
}
