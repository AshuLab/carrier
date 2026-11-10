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
}

/// Which of the Sessions, Carrier and Archive sections is unfolded; the others are folded.
public enum OpenSection: String { case sessions, carrier, archive }

/// The modifier keys a shortcut can carry.
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
    /// The session after or before the open one in the order the sidebar shows, stopping at the ends.
    case nextSession, previousSession
    /// Archive the open session.
    case archiveSession
    /// Something in the open conversation; nothing without one.
    case conversation(ConversationAction)
}

/// What a shortcut asks of the open conversation.
public enum ConversationAction: Equatable {
    case focusBox, stopAgent, jumpToLatest, toggleToolFolds, copyLastAnswer
}

/// A request to the open conversation; `count` makes asking twice a change the view can see.
public struct ConversationRequest: Equatable {
    public let action: ConversationAction
    public let count: Int
}

/// The action a key runs, from the shortcut table; a combination no action has, or one without ⌘, ⌃ or ⌥, is nothing. `key` is the character
/// without modifiers.
public func shortcutAction(key: String, modifiers: ShortcutModifiers, in table: ShortcutTable = ShortcutTable()) -> ShortcutAction? {
    KeyCombo(key: key, modifiers: modifiers).flatMap { table.command(for: $0)?.action }
}

/// A request to open the search of a section; `count` makes asking twice a change the views can see.
public struct SearchRequest: Equatable {
    public let section: OpenSection
    public let count: Int
}

/// A request to archive the open session; `count` makes asking twice a change the views can see.
public struct ArchiveRequest: Equatable {
    public let sessionId: String
    public let count: Int
}

@Observable public final class WindowShell {
    /// Choosing the Sessions home or a session opens Sessions, an epic or the Carrier home opens the card, Archive opens its list; the
    /// rest leave it. `chooseArchived` puts Archive back after choosing a session from its list.
    public var selection: Selection = .home {
        didSet {
            if selection == .newSession { newSessionOpened += 1 }
            switch selection {
            case .sessions, .session, .newSession: open = .sessions
            case .carrier, .epic: open = .carrier
            case .archive: open = .archive
            case .home: break
            }
        }
    }
    /// Counts the times New session was asked for, the + while its draft is already open included: the draft starts blank each time.
    public private(set) var newSessionOpened = 0
    /// The Settings sheet is over the window, on this section; the selection underneath stays.
    public var settingsShown = false
    public var settingsTab = SettingsPage.general
    /// The unfolded section; nil when all are folded.
    public var open: OpenSection?
    public var sidebarShown = true
    public var inspectorShown = true
    /// The last ⌘F, for the open section's search to show itself.
    public private(set) var searchRequest: SearchRequest?
    /// The last request to the open conversation.
    public private(set) var conversationRequest: ConversationRequest?
    /// The last ⇧⌘A, for the window to archive that session through the host.
    public private(set) var archiveRequest: ArchiveRequest?

    public init(open: OpenSection? = .sessions) { self.open = open }

    /// Choosing a session from the Archive list: selecting it unfolds Sessions, so Archive is put back and the list chosen from stays.
    public func chooseArchived(_ id: String) {
        selection = .session(id: id)
        open = .archive
    }

    /// Opens the Settings sheet on a page; it starts on the first one unless something asks for another.
    public func showSettings(_ tab: SettingsPage = .general) {
        settingsTab = tab
        settingsShown = true
    }

    /// A reason that points to the Health tab (a provider, `gh` or `git` that cannot be used) opens it.
    public func openHealth() { showSettings(.health) }

    public func toggleSidebar() { sidebarShown.toggle() }
    public func toggleInspector() { inspectorShown.toggle() }

    /// Runs a shortcut: a selection as a click on it would, ⌘F as a request to the open section (nothing with both folded). The
    /// session shortcuts read `sessions` in the order `sort` gives the sidebar; with none open, next picks the first and previous the last.
    public func perform(_ action: ShortcutAction, sessions: [SessionRow] = [], sort: SessionSort = .workspace, pinned: Set<String> = []) {
        switch action {
        case .select(let next): selection = next
        case .search:
            if let open { searchRequest = SearchRequest(section: open, count: (searchRequest?.count ?? 0) + 1) }
        case .nextSession, .previousSession:
            let ids = sessionGroups(sessions, by: sort, pinned: pinned).flatMap(\.rows).map(\.id)
            let step = action == .nextSession ? 1 : -1
            var current: Int?
            if case .session(let id) = selection { current = ids.firstIndex(of: id) }
            let target = current.map { $0 + step } ?? (step > 0 ? 0 : ids.count - 1)
            if ids.indices.contains(target) { selection = .session(id: ids[target]) }
        case .archiveSession:
            if case .session(let id) = selection, sessions.contains(where: { $0.id == id && $0.archived == false }) {
                archiveRequest = ArchiveRequest(sessionId: id, count: (archiveRequest?.count ?? 0) + 1)
            }
        case .conversation(let action):
            if case .session = selection { conversationRequest = ConversationRequest(action: action, count: (conversationRequest?.count ?? 0) + 1) }
        }
    }

    /// Back to how a freshly opened window starts.
    public func reset(open: OpenSection? = .sessions) {
        selection = .home
        self.open = open
        sidebarShown = true
        inspectorShown = true
        settingsShown = false
        searchRequest = nil
        conversationRequest = nil
        archiveRequest = nil
    }
}
