import Foundation

// The app's shortcuts as one table (docs/specs/settings-app-group.md, Keybindings): the menu and the key monitor both read it, and the
// person's own combinations are kept in the preferences.

/// A key with the modifiers pressed with it. A shortcut needs ⌘, ⌃ or ⌥: a bare key or ⇧ and a key is typing, not a shortcut.
public struct KeyCombo: Equatable {
    /// The character without modifiers, lowercased.
    public let key: String
    public let modifiers: ShortcutModifiers

    public init?(key: String, modifiers: ShortcutModifiers) {
        let key = key.lowercased()
        // the left and right arrows and the function keys come as private characters with no glyph: only the up and down arrows are kept
        guard key.count == 1, key == Self.downArrow || key == Self.upArrow || key.unicodeScalars.allSatisfy({ ![.control, .privateUse].contains($0.properties.generalCategory) }),
            modifiers.isDisjoint(with: [.command, .control, .option]) == false
        else { return nil }
        self.key = key
        self.modifiers = modifiers
    }

    /// The keys the Edit and application menus keep for the system (cut, copy, paste, select all, undo, redo, quit, close, minimize, hide
    /// and Settings): giving one to an action would break it in the window.
    public var isReserved: Bool {
        (modifiers == .command && "xcvazqwmh,".contains(key)) || (modifiers == [.command, .shift] && key == "z")
    }

    /// As the menus write it: ⌃⌥⇧⌘ and the key.
    public var text: String {
        let symbols = [(ShortcutModifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + (Self.arrows[key] ?? key.uppercased())
    }

    /// The up and down arrows as the keyboard reports them (NSUpArrowFunctionKey, NSDownArrowFunctionKey), and how they are written.
    static let upArrow = "\u{F700}"
    static let downArrow = "\u{F701}"
    private static let arrows = [upArrow: "↑", downArrow: "↓"]

    /// The form kept in the preferences: the modifiers, a colon, the key.
    var stored: String { "\(modifiers.rawValue):\(key)" }

    init?(stored: String) {
        let parts = stored.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let raw = Int(parts[0]) else { return nil }
        self.init(key: String(parts[1]), modifiers: ShortcutModifiers(rawValue: raw))
    }
}

/// A group of the Keybindings page; the raw value is its identifier.
public enum ShortcutGroup: String, CaseIterable {
    case goTo = "go-to", sessions, conversation, carrier

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .goTo: Copy.shortcutGroupGoTo(bundle: bundle, locale: locale)
        case .sessions: Copy.shortcutGroupSessions(bundle: bundle, locale: locale)
        case .conversation: Copy.shortcutGroupConversation(bundle: bundle, locale: locale)
        case .carrier: Copy.shortcutGroupCarrier(bundle: bundle, locale: locale)
        }
    }
}

/// An action that has a shortcut; the raw value is its id.
public enum ShortcutCommand: String, CaseIterable {
    case home, sessions, carrier, archive, back, forward, newSession, search, nextSession, previousSession, archiveSession
    case focusBox, stopAgent, latestMessage, foldTools, copyAnswer
    case startOrStop, pauseOrResume, checkNow

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .home: Copy.shortcutHome(bundle: bundle, locale: locale)
        case .sessions: Copy.shortcutSessions(bundle: bundle, locale: locale)
        case .carrier: Copy.shortcutCarrier(bundle: bundle, locale: locale)
        case .archive: Copy.shortcutArchive(bundle: bundle, locale: locale)
        case .back: Copy.shortcutBack(bundle: bundle, locale: locale)
        case .forward: Copy.shortcutForward(bundle: bundle, locale: locale)
        case .newSession: Copy.shortcutNewSession(bundle: bundle, locale: locale)
        case .search: Copy.shortcutSearch(bundle: bundle, locale: locale)
        case .nextSession: Copy.shortcutNextSession(bundle: bundle, locale: locale)
        case .previousSession: Copy.shortcutPreviousSession(bundle: bundle, locale: locale)
        case .archiveSession: Copy.shortcutArchiveSession(bundle: bundle, locale: locale)
        case .focusBox: Copy.shortcutFocusBox(bundle: bundle, locale: locale)
        case .stopAgent: Copy.shortcutStopAgent(bundle: bundle, locale: locale)
        case .latestMessage: Copy.shortcutLatestMessage(bundle: bundle, locale: locale)
        case .foldTools: Copy.shortcutFoldTools(bundle: bundle, locale: locale)
        case .copyAnswer: Copy.shortcutCopyAnswer(bundle: bundle, locale: locale)
        case .startOrStop: Copy.shortcutStartOrStop(bundle: bundle, locale: locale)
        case .pauseOrResume: Copy.shortcutPauseOrResume(bundle: bundle, locale: locale)
        case .checkNow: Copy.shortcutCheckNow(bundle: bundle, locale: locale)
        }
    }

    public var group: ShortcutGroup {
        switch self {
        case .home, .sessions, .carrier, .archive, .back, .forward: .goTo
        case .newSession, .search, .nextSession, .previousSession, .archiveSession: .sessions
        case .focusBox, .stopAgent, .latestMessage, .foldTools, .copyAnswer: .conversation
        case .startOrStop, .pauseOrResume, .checkNow: .carrier
        }
    }

    /// What the window does when it runs; nil for the Carrier controls, which the menu runs.
    public var action: ShortcutAction? {
        switch self {
        case .home: .select(.home)
        case .sessions: .select(.sessions)
        case .carrier: .select(.carrier)
        case .archive: .select(.archive)
        case .back: .back
        case .forward: .forward
        case .newSession: .select(.newSession)
        case .search: .search
        case .nextSession: .nextSession
        case .previousSession: .previousSession
        case .archiveSession: .archiveSession
        case .focusBox: .conversation(.focusBox)
        case .stopAgent: .conversation(.stopAgent)
        case .latestMessage: .conversation(.jumpToLatest)
        case .foldTools: .conversation(.toggleToolFolds)
        case .copyAnswer: .conversation(.copyLastAnswer)
        case .startOrStop, .pauseOrResume, .checkNow: nil
        }
    }

    /// ⌘ and a key; nil is no shortcut until the person gives one.
    public var defaultCombo: KeyCombo? {
        switch self {
        case .home: KeyCombo(key: "1", modifiers: .command)
        case .sessions: KeyCombo(key: "2", modifiers: .command)
        case .carrier: KeyCombo(key: "3", modifiers: .command)
        case .archive: KeyCombo(key: "4", modifiers: .command)
        case .newSession: KeyCombo(key: "n", modifiers: .command)
        case .search: KeyCombo(key: "f", modifiers: .command)
        case .back: KeyCombo(key: "[", modifiers: .command)
        case .forward: KeyCombo(key: "]", modifiers: .command)
        case .nextSession: KeyCombo(key: KeyCombo.downArrow, modifiers: [.command, .option])
        case .previousSession: KeyCombo(key: KeyCombo.upArrow, modifiers: [.command, .option])
        case .archiveSession: KeyCombo(key: "a", modifiers: [.command, .shift])
        case .focusBox: KeyCombo(key: "l", modifiers: .command)
        case .stopAgent: KeyCombo(key: ".", modifiers: .command)
        case .latestMessage: KeyCombo(key: KeyCombo.downArrow, modifiers: .command)
        case .foldTools: KeyCombo(key: "e", modifiers: [.command, .option])
        case .copyAnswer: KeyCombo(key: "c", modifiers: [.command, .shift])
        case .startOrStop, .pauseOrResume, .checkNow: nil
        }
    }
}

/// Each action's combination: the person's own where they set one, the default where not. A cleared one is none; a bad saved value reads
/// as the default.
public struct ShortcutTable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private var saved: [String: String] { defaults.dictionary(forKey: Preference.keybindings.name) as? [String: String] ?? [:] }

    public func combo(for command: ShortcutCommand) -> KeyCombo? {
        guard let value = saved[command.rawValue] else { return command.defaultCombo }
        if value.isEmpty { return nil }
        return KeyCombo(stored: value) ?? command.defaultCombo
    }

    /// Every action's combination, in the table's order: what the menu was built from, to know when it is out of date.
    public var combos: [KeyCombo?] { ShortcutCommand.allCases.map { combo(for: $0) } }

    /// Keeps a combination for an action, nil to clear it; the default is kept as no override.
    public func set(_ combo: KeyCombo?, for command: ShortcutCommand) {
        var next = saved
        next[command.rawValue] = combo == command.defaultCombo ? nil : combo?.stored ?? ""
        defaults.set(next, forKey: Preference.keybindings.name)
    }

    public func isDefault(_ command: ShortcutCommand) -> Bool { combo(for: command) == command.defaultCombo }

    /// The action that runs for a combination; on a clash, the first of the table.
    public func command(for combo: KeyCombo) -> ShortcutCommand? { ShortcutCommand.allCases.first { self.combo(for: $0) == combo } }

    /// Another action that has this combination.
    public func clash(of combo: KeyCombo, for command: ShortcutCommand) -> ShortcutCommand? {
        ShortcutCommand.allCases.first { $0 != command && self.combo(for: $0) == combo }
    }
}
