import Foundation
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
    case terminals
    case terminal(id: UUID)
    case archive
    case carrier
    /// The Usage page of the sidebar foot, under Settings: quotas and consumption, not a section with a list of its own.
    case usage
    case epic(repo: String, issue: Int)
}

/// Which of the Sessions, Terminal, Carrier and Archive sections is unfolded; the others are folded.
public enum OpenSection: String { case sessions, terminal, carrier, archive }

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
    /// Back and forward through the places chosen, as the toolbar's ‹ and › do.
    case back, forward
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
    /// The Stop button in a subagent view's header: not a shortcut, the header is the window's and the conversation holds the host.
    case stopSubagent
    /// The global shortcut: focus the message box and start or stop its dictation.
    case dictate
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
            history.visit(selection)
            if selection == .newSession, navigating == false { newSessionOpened += 1 }
            subagents = []
            subagentHeader = nil
            switch selection {
            case .sessions, .session, .newSession: open = .sessions
            case .terminals, .terminal: open = .terminal
            case .carrier, .epic: open = .carrier
            case .archive: open = .archive
            case .home, .usage: break
            }
        }
    }
    /// A session that was archived or deleted while it is on screen has nothing to show: the window goes to a new session, where the next task starts.
    public func sessionRemoved(_ id: String) {
        if selection == .session(id: id) { selection = .newSession }
        history.forget(.session(id: id))
    }

    /// The places the selection has been at; ‹ and › in the window's toolbar walk it. Every change of the selection is a visit.
    public private(set) var history = SelectionHistory()

    /// ‹: the selection goes to the one before. The history is already there, so the selection's visit adds nothing.
    /// The draft of a new session is kept: going back to it is not opening it, which starts it blank.
    public func goBack() {
        history.back()
        navigate(to: history.current)
    }

    /// ›: the selection goes to the one after.
    public func goForward() {
        history.forward()
        navigate(to: history.current)
    }

    @ObservationIgnored private var navigating = false

    private func navigate(to place: Selection) {
        navigating = true
        selection = place
        navigating = false
    }

    /// A terminal that was closed leaves the history, as a session that is gone does.
    public func terminalRemoved(_ id: UUID) { history.forget(.terminal(id: id)) }

    /// The subagent views open over the open conversation, outermost first, each the call that launched it: Back leaves the last. A session
    /// is left with none open.
    public var subagents: [String] = []
    /// What the window's header says of the last one, set by the conversation, which has the events; nil with none open.
    public var subagentHeader: SubagentHeader?
    /// Counts the times New session was asked for, the + while its draft is already open included: the draft starts blank each time.
    public private(set) var newSessionOpened = 0
    /// The unfolded section; nil when all are folded.
    public var open: OpenSection?
    public var sidebarShown = true
    public var inspectorShown = true
    /// Terminal owners (chat sessions or epics) whose bottom embedded-terminal drawer is currently expanded.
    public var terminalDrawerOwners: Set<TerminalOwner> = []
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

    public func openSubagent(_ call: String) { subagents.append(call) }
    /// Back: one level up, to the subagent that launched this one or to the conversation.
    public func leaveSubagent() { _ = subagents.popLast() }

    public func toggleSidebar() { sidebarShown.toggle() }
    public func toggleInspector() { inspectorShown.toggle() }

    public func isTerminalDrawerOpen(for owner: TerminalOwner) -> Bool {
        terminalDrawerOwners.contains(owner)
    }

    public func setTerminalDrawerOpen(_ open: Bool, for owner: TerminalOwner) {
        if open {
            terminalDrawerOwners.insert(owner)
        } else {
            terminalDrawerOwners.remove(owner)
        }
    }

    public func toggleTerminalDrawer(for owner: TerminalOwner) {
        setTerminalDrawerOpen(isTerminalDrawerOpen(for: owner) == false, for: owner)
    }

    /// Runs a shortcut: a selection as a click on it would, ⌘F as a request to the open section (nothing with both folded). The
    /// session shortcuts read `sessions` in the order `sort` gives the sidebar; with none open, next picks the first and previous the last.
    public func perform(_ action: ShortcutAction, sessions: [SessionRow] = [], sort: SessionSort = .workspace, pinned: Set<String> = []) {
        switch action {
        case .select(let next): selection = next
        case .search:
            if let open { searchRequest = SearchRequest(section: open, count: (searchRequest?.count ?? 0) + 1) }
        case .back: goBack()
        case .forward: goForward()
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
            // the draft of a new session has a message box too, which takes the two actions that are about a box
            let asked: Bool
            switch selection {
            case .session: asked = true
            case .newSession: asked = action == .focusBox || action == .dictate
            default: asked = false
            }
            if asked { conversationRequest = ConversationRequest(action: action, count: (conversationRequest?.count ?? 0) + 1) }
        }
    }

    /// Back to how a freshly opened window starts.
    public func reset(open: OpenSection? = .sessions) {
        selection = .home
        history = SelectionHistory()
        self.open = open
        sidebarShown = true
        inspectorShown = true
        terminalDrawerOwners = []
        searchRequest = nil
        conversationRequest = nil
        archiveRequest = nil
    }
}
