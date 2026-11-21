import Foundation

// What Settings can be searched for: every page, and the groups and rows of each, with the words the person sees. The window's search reads
// this (`settingsResults`) and the page scrolls to the row that was chosen, found again by `settingsAnchor`.
// A row or a group that is not here cannot be found, so a new one is added here in the same change: `SettingsIndexTests` fails when a title the
// views draw is not in this list, and when a title in this list is no longer drawn.

/// The place a row has in Settings: its page, the group of rows it is in ("" for the page itself) and its title.
public struct SettingsEntry: Equatable, Sendable, Identifiable {
    public let page: SettingsPage
    public let group: String
    public let title: String
    public let detail: String
    /// The page itself, found by its name: choosing it goes to the page, not to a row.
    public let isPage: Bool
    /// The screen inside the page this opens, for what only this Mac knows (a provider, an account); empty for a row of the page.
    public let path: [String]

    public init(page: SettingsPage, group: String = "", title: String, detail: String = "", isPage: Bool = false, path: [String] = []) {
        self.page = page
        self.group = group
        self.title = title
        self.detail = detail
        self.isPage = isPage
        self.path = path
    }

    /// What the page scrolls to once the place is open: the row's own anchor (`settingsAnchor`), the page's name for a page.
    public var anchor: String { isPage ? settingsAnchor(page, group: "", title: "") : settingsAnchor(page, group: group, title: title) }

    /// What a row of a list is known by: the anchor, and with its path for a screen (two accounts of one provider may share a name).
    public var id: String { path.isEmpty ? anchor : ([anchor] + path).joined(separator: "/") }
}

/// The id a row carries in its page, so the page can scroll to it: its page, its group and its title as slugs. A group is its own title with no
/// row (`title` empty or the same as the group's), and a page is its name alone.
public func settingsAnchor(_ page: SettingsPage, group: String, title: String) -> String {
    func slug(_ text: String) -> String {
        text.lowercased().split { $0.isLetter == false && $0.isNumber == false }.joined(separator: "-")
    }
    return [page.rawValue, group, title == group ? "" : title].map(slug).filter { $0.isEmpty == false }.joined(separator: ".")
}

private func page(_ page: SettingsPage, _ group: String, _ rows: [(String, String)], path: [String] = []) -> [SettingsEntry] {
    rows.map { SettingsEntry(page: page, group: group, title: $0.0, detail: $0.1, path: path) }
}

/// Every searchable place, in the order of the sidebar and of each page, so a search lists its results as the pages are listed.
public let settingsIndex: [SettingsEntry] = SettingsPage.allCases.flatMap { settingsPage in
    [SettingsEntry(page: settingsPage, title: settingsPage.rawValue, detail: settingsPage.detail, isPage: true)] + settingsRows(settingsPage)
}

private func settingsRows(_ settingsPage: SettingsPage) -> [SettingsEntry] {
    switch settingsPage {
    case .general:
        return page(.general, "Menu bar", [
            ("Icon style", "What the icon in the menu bar shows"), ("Animate the icon", "A segment moves over the bar while epics run"),
            ("List epics in the menu", "The epics that run or wait show under the status"),
        ]) + page(.general, "Display", [
            ("Time format", "Ages read \"11m\" or as a time, \"14:32\""), ("Clock", "How clock times count the hours"),
        ])
    case .providers:
        return page(.providers, "Accounts that need attention", [("Accounts that need attention", "Signed out, or near the limit of the 5h window")])
            + page(.providers, "AI providers", [("AI providers", "The tools of this Mac, each with its accounts")])
            + page(.providers, "Local servers", [("Local servers", "LM Studio and Ollama, and the models they have loaded")])
    case .appearance:
        return page(.appearance, "Theme", [("Theme", "Nine themes, each in light and dark")])
            + page(.appearance, "Look", [
                ("Color scheme", "System follows the Mac"), ("Text size", "The size of the text of the whole app"), ("Icon set", "SF Symbols, Tabler or Lucide for the icons of the app"), ("Icon weight", "How thick the strokes of the icons are"),
                ("Density", "The space in the sidebar rows and between the messages"), ("Tell states apart by shape", "A symbol in each state, so that color is not the only clue"),
            ]) + page(.appearance, "Color", [
                ("Accent color", "Buttons, switches and the selection"), ("Tint the windows", "A touch of the theme's own color on the backgrounds"),
                ("Translucent windows", "Off draws solid backgrounds"),
            ]) + page(.appearance, "Code and output", [
                ("Font", "The monospaced fonts installed on this Mac"), ("Size", "In points, before the text size of the whole app"),
                ("Line height", "The room between the lines of code and output"), ("Ligatures", "Joins pairs such as != and >= where the font has them"),
                ("Wrap long lines", "Off keeps each line whole and scrolls sideways"), ("Line numbers", "In code blocks and the output of a command"),
            ])
    case .notifications:
        return page(.notifications, "Carrier", [
            ("Needs attention", "An epic stopped and waits for a person"), ("Ready for test", "An epic finished and has a PR to try"),
            ("A problem", "GitHub refuses a repo, or Carrier stops by itself"),
        ]) + page(.notifications, "Chat", [("Needs attention", "A session waits for an approval"), ("Done", "A session finished its turn")])
            + page(.notifications, "Delivery", [
                ("Only when Carrier is not in front", "No banner while its window is the one you are looking at"),
                ("Dock badge", "The Dock icon counts what needs a person"), ("Play a sound", "A banner plays the notification sound"),
                ("Remind me again", "While something still needs attention"), ("Quiet hours", "Notifications wait in the Notification Center"),
                ("From", "When the quiet starts"), ("Until", "When it ends"),
            ]) + page(.notifications, "Permission", [("System permission", "Whether macOS lets Carrier send notifications")])
    case .keybindings:
        return ShortcutGroup.allCases.flatMap { group in
            page(.keybindings, group.rawValue, ShortcutCommand.allCases.filter { $0.group == group }.map { ($0.title, "Default: \($0.defaultCombo?.text ?? "none")") })
        }
    case .dictation:
        func screen(_ screen: DictationScreen, _ group: String, _ rows: [(String, String)]) -> [SettingsEntry] { page(.dictation, group, rows, path: [screen.rawValue]) }
        // the rows of the first screen that open a screen are the way to it from a search
        let opens = DictationScreen.allCases.map { SettingsEntry(page: .dictation, group: $0 == .history || $0 == .statistics ? "Your dictations" : "Set up", title: $0.title, detail: $0.detail, path: [$0.rawValue]) }
        return opens + page(.dictation, "Dictation", [("Microphone", "Whether Carrier may listen, in the card at the top")])
            + screen(.recognition, "Speech models", [("Speech models", "The models you can download, choose and delete")])
            + screen(.recognition, "", [("Language", "What you speak")])
            + screen(.recognition, "Memory", [
                ("Keep the speech model ready", "Loads it when Carrier opens, so the first dictation does not wait"),
                ("Release the model after", "Without dictating, to give its memory back"),
            ])
            + screen(.recognition, "Storage", [("Downloaded models", "How much space the models take")])
            + screen(.global, "Global dictation", [
                ("Dictate in any app", "Opens a widget in any app, and pastes what you say"), ("Accessibility", "What lets Carrier paste into another app"),
                ("Shortcut", "With Carrier in front on a session it dictates into the message box"), ("Activation", "Toggle, or hold the keys while you speak"),
            ])
            + screen(.global, "Widget", [("Widget style", "Pill, Small, Medium or Large"), ("Position", "Top or bottom centre, on the display of the window in front")])
            + screen(.cleanup, "Cleanup", [
                ("Clean the text with a model", "Runs on this Mac; nothing leaves it"), ("Server", "Where the local model runs"),
                ("Model", "The model that cleans the text"), ("Prompt", "What you ask the model to do with every dictation"), ("Try it", "Runs the prompt on a sample"),
            ])
            + screen(.sounds, "Sounds", [("Start sound", "Plays when it begins to listen"), ("End sound", "Plays when it stops listening"), ("Volume", "For both sounds, in the global dictation only")])
            + screen(.history, "History", [
                ("Keep the text of my dictations", "A list with search, copy and delete, on this Mac"), ("Keep the audio", "Each recorded dictation has its audio to play back"),
                ("Delete audio older than", "The transcripts stay"), ("Audio on disk", "How much space the audio takes"),
            ])
            + screen(.statistics, "Overview", [("Overview", "Dictations, words, speaking time and time saved, by range")])
            + screen(.statistics, "By hour of the day", [("By hour of the day", "When you dictate most")])
            + screen(.statistics, "This week", [("This week", "The last 7 days against the 7 before")])
            + screen(.statistics, "Records", [("Records", "Your best day, your longest dictation and your longest streak")])
            + screen(.statistics, "Statistics settings", [("Typing speed", "Used for the time saved"), ("Reset statistics", "Deletes the counters; the history stays")])
    case .keepAwake:
        return page(.keepAwake, "Now", [("Now", "Whether the Mac is being kept awake, and the button that turns it on or off")])
            + page(.keepAwake, "By hand", [
                ("Length", "What the menu's Keep awake item and the shortcut start"), ("Keep the screen on", "Off lets the screen sleep while the Mac stays awake"),
                ("Shortcut", "Turns keep awake on or off from any app"),
            ])
            + page(.keepAwake, "With agents", [
                ("Keep awake while agents work", "While an epic runs or a session works"), ("Stay awake after they finish", "Time to read the result before the Mac may sleep"),
            ])
            + page(.keepAwake, "Battery and notices", [
                ("On battery", "What it does when the Mac runs on battery"), ("Tell me when it stops by itself", "A notification when the time runs out or the battery ends it"),
            ])
    case .chat:
        return page(.chat, "Message box", [
            ("Send with", "The other key makes a new line"), ("While the agent works", "Hold the message, or stop the turn and send it"),
            ("Writing Tools", "The system's offer to rewrite or proofread what you select"), ("Check spelling", "Underline words that look misspelled"),
            ("Correct spelling automatically", "Fix a misspelled word as you type it"),
        ]) + page(.chat, "Conversation", [
            ("Follow new output", "Scroll to what arrives while you are at the end"), ("Message times", "When a message shows the time it was written"),
            ("Tool output", "Nothing, each run folded, or every call open"), ("Open the calls that failed", "A call that failed opens by itself"),
            ("Diff style", "Unified, or removed and added side by side"), ("Output length", "How many lines of an output show before Show more"),
            ("Show reasoning", "The agent's reasoning, folded under its message"), ("Message width", "How wide a message gets before it wraps"),
            ("Surfaces", "Glass blurs what is under; flat is a quiet solid fill"),
        ])
    case .sessions:
        return page(.sessions, "New sessions", [("Starts with", "Provider, model and reasoning"), ("Work in", "Base folder or a new worktree"),
            ("Start from", "Where a new worktree is cut: the remote branch (latest) or the local branch")])
            + page(.sessions, "Idle sessions", [
                ("Sleep after", "How long an idle session nobody opens keeps its agent running before it closes and falls asleep, freeing its memory (the timeout of an inactive session, or inactivity timeout): 10 minutes, 30 minutes or 1 hour"),
            ]) + page(.sessions, "Archive and delete", [
                ("Archive after", "Days without activity before it is archived"), ("Delete after", "Days an archived session waits before it is deleted"),
                ("Ask before deleting a session", "The question says its worktree goes with it"),
            ]) + page(.sessions, "With these ages", [("With these ages", "What the ages do to a session left alone from today")])
    case .sidebar:
        return page(.sidebar, "Order", [
            ("Group epics by", "How the epics under Carrier are grouped"), ("Sort sessions", "How the Sessions list is grouped and ordered"),
            ("Sort the Archive", "How the archived sessions are ordered"),
        ]) + page(.sidebar, "Session rows", [
            ("Project icon", "The colored square with the project's initials"), ("Branch", "Where the session works, the branch or the base folder"),
            ("Pull request", "The pull request of the session's branch, with its state and checks"), ("Lines changed", "How many lines the session added and removed"),
            ("Providers", "The marks of the providers the session used"), ("Age", "How long ago the session was last active"),
        ])
    case .terminal:
        return page(.terminal, "Appearance", [
            ("Theme", "Color palette for panes; inherits the app theme by default"), ("Minimum contrast", "Raises low-contrast ANSI text"),
            ("Horizontal padding", "Left and right margin inside each pane"), ("Vertical padding", "Top and bottom margin inside each pane"),
        ]) + page(.terminal, "Typography", [
            ("Font", "Monospaced font used in panes; inherits Appearance › Code and output"), ("Size", "Text size in points for terminal output"),
            ("Ligatures", "Joins pairs such as != and >= where the font has them"), ("Thicken font", "Renders glyphs slightly heavier on Retina displays"),
        ]) + page(.terminal, "Cursor", [("Cursor style", "Shape of the text cursor inside terminal panes"), ("Blink cursor", "Animates the cursor when the pane is focused")])
            + page(.terminal, "Panes", [
                ("Dim inactive panes", "Softens unfocused split panes so the active pane stands out"),
                ("Focus follows mouse", "Activates split panes when hovering over them without clicking"),
            ]) + page(.terminal, "Input and scrollback", [
                ("Option as Alt", "Sends Option key presses as Meta/Alt escape sequences in shells"),
                ("Copy on select", "Copies highlighted terminal text to the clipboard automatically"), ("Scrollback limit", "Memory reserved per pane for scrollback output history"),
            ]) + page(.terminal, "Shell and closing", [
                ("Pin Zsh prompt to bottom", "Keeps new interactive prompts at the bottom row without changing dotfiles"),
                ("Confirm before closing running commands", "Asks before closing a tab, split, or drawer with an active process"),
            ])
    case .agents:
        // the rows of a role's screen are the same for the three roles: the search opens the Author's, and the Lead reviewer's switch opens its own
        let role = [AgentRole.author.rawValue]
        var entries = page(.agents, "How an epic runs", AgentRole.allCases.map { ($0.title, $0.purpose) })
        entries += page(.agents, "Identities", [("Create a bot…", "Opens Terminal on agent-forge add, to make a GitHub identity for a role")])
        entries += page(.agents, "", [("Use a lead reviewer", "A second reviewer checks the first")], path: [AgentRole.leadReviewer.rawValue])
        entries += page(.agents, "Who", [("Identity", "The GitHub identity an agent acts as"), ("Model", "The model and reasoning of the role")], path: role)
        entries += page(.agents, "Persona", [("Persona name", "Optional, one line up to 40 characters"), ("Persona prompt", "Optional instructions")], path: role)
        for skillRole in AgentRole.allCases {
            var rows = skillRole.stages.map { ($0.title, "\($0.detail). Runs the skill \($0.skill)") }
            if skillRole.stages.isEmpty { rows.append(("Not used by the engine yet", "The Lead reviewer has no stage, so no skill")) }
            entries += page(.agents, "Skills", rows, path: [skillRole.rawValue])
        }
        entries += page(.agents, "When it runs out of tokens", [("Switch automatically", "Usage limit, rate limit or service down")], path: role)
        return entries
    case .repos:
        return page(.repos, "Status", [("Status", "What Carrier watches in each repo")])
            + page(.repos, "Who works here", [("Defaults", "Every repo follows the roles of Agents unless it has its own")])
    case .behavior:
        return behaviorGroups.flatMap { group in page(.behavior, group.title, group.rows.map { ($0.title, $0.detail) }) }
    case .engine:
        return page(.engine, "Starting", [
            ("Start Carrier when the app opens", "Carrier starts working on ready epics as soon as the app opens"),
            ("Ask before stopping Carrier", "Only when stopping would interrupt epics that are running"),
        ]) + page(.engine, "Programs", [
            ("carrier", "The program the app runs"), ("node", "What runs it"), ("PATH", "Where the app looks for tools"),
            ("Look for the tools again", "Looks for carrier and node again"),
        ]) + page(.engine, "GitHub identity", [("Carrier acts on GitHub as", "Reads issues and PRs and changes labels")])
            + page(.engine, "Files", [
                ("Carrier folder", "Where Carrier keeps its config, clones and logs"), ("Logs", "What Carrier wrote while it ran"),
                ("Start log", "What the app saw the last time it started Carrier"),
            ])
    case .health:
        return page(.health, "This Mac", [("This Mac", "The tools the chat needs: git, gh and your AI providers")])
            + page(.health, "Carrier", [("Chat host", "Whether the chat host runs"), ("Engine", "Whether the engine runs")])
    case .about:
        return page(.about, "About", [("Star Carrier on GitHub", "A star helps other people find it")])
            + page(.about, "Updates", [
                ("Check by itself", "Looks for a newer Carrier when it opens and from time to time"),
                ("Install by itself", "Installs when you quit; off, it asks before it installs"), ("Update delay", "Waits this long after a release before offering it"),
            ]) + page(.about, "Engine", [("Engine and chat host", "The engine's own update")])
    }
}

/// The places that match `query`, best first: every word of it has to be in the title, the group, the page or the description (case and accents
/// ignored); a match in the title goes before one in the group or the page, and that before one in the description. The same rank keeps the
/// order of the sidebar and of the page.
public func settingsResults(_ query: String, in entries: [SettingsEntry] = settingsIndex) -> [SettingsEntry] {
    func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    guard words.isEmpty == false else { return [] }
    func rank(_ entry: SettingsEntry) -> Int? {
        let title = fold(entry.title), place = fold(entry.group + " " + entry.page.rawValue), detail = fold(entry.detail)
        guard words.allSatisfy({ title.contains($0) || place.contains($0) || detail.contains($0) }) else { return nil }
        if words.allSatisfy({ title.contains($0) }) { return 0 }
        if words.allSatisfy({ title.contains($0) || place.contains($0) }) { return 1 }
        return 2
    }
    return entries.enumerated().compactMap { index, entry in rank(entry).map { (rank: $0, index: index, entry: entry) } }
        .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.map(\.entry)
}
