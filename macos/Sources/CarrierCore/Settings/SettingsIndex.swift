import Foundation

// What Settings can be searched for: every page, and the groups and rows of each, with the words the person sees. The window's search reads
// this (`settingsResults`) and the page scrolls to the row that was chosen, found again by `settingsAnchor`.
// A place is known by identifiers (the page's, the group's, the row's), never by its title, so a title can change or be translated and nothing
// that finds it breaks. A row or a group that is not here cannot be found, so a new one is added here in the same change:
// `SettingsIndexDriftTests` fails when a row the views draw has an identifier that is not in this list, and when one in this list is no longer drawn.

/// The place a row has in Settings: its page, the group of rows it is in ("" for the page itself) and its title, each group and row with the
/// identifier its view carries (`SettingsTabRow(id:)`).
public struct SettingsEntry: Equatable, Sendable, Identifiable {
    public let page: SettingsPage
    public let groupID: String
    public let group: String
    public let rowID: String
    public let title: String
    public let detail: String
    /// The page itself, found by its name: choosing it goes to the page, not to a row.
    public let isPage: Bool
    /// The screen inside the page this opens, for what only this Mac knows (a provider, an account); empty for a row of the page.
    public let path: [String]

    public init(
        page: SettingsPage, groupID: String = "", group: String = "", rowID: String = "", title: String, detail: String = "", isPage: Bool = false, path: [String] = []
    ) {
        self.page = page
        self.groupID = groupID
        self.group = group
        self.rowID = rowID
        self.title = title
        self.detail = detail
        self.isPage = isPage
        self.path = path
    }

    /// What the page scrolls to once the place is open: the row's own anchor (`settingsAnchor`), the page's identifier for a page.
    public var anchor: String { isPage ? settingsAnchor(page, group: "", row: "") : settingsAnchor(page, group: groupID, row: rowID) }

    /// What a row of a list is known by: the anchor, and with its path for a screen (two accounts of one provider may share a name).
    public var id: String { path.isEmpty ? anchor : ([anchor] + path).joined(separator: "/") }
}

/// The id a row carries in its page, so the page can scroll to it: the identifiers of its page, its group and its row. A group is its own
/// identifier with no row (`row` empty or the same as the group's), and a page is its identifier alone.
public func settingsAnchor(_ page: SettingsPage, group: String, row: String) -> String {
    [page.rawValue, group, row == group ? "" : row].filter { $0.isEmpty == false }.joined(separator: ".")
}

private func page(_ page: SettingsPage, _ groupID: String, _ group: String, _ rows: [(id: String, title: String, detail: String)], path: [String] = []) -> [SettingsEntry] {
    rows.map { SettingsEntry(page: page, groupID: groupID, group: group, rowID: $0.id, title: $0.title, detail: $0.detail, path: path) }
}

/// Every searchable place, in the order of the sidebar and of each page, so a search lists its results as the pages are listed.
public let settingsIndex: [SettingsEntry] = SettingsPage.allCases.flatMap { settingsPage in
    [SettingsEntry(page: settingsPage, title: settingsPage.title, detail: settingsPage.detail, isPage: true)] + settingsRows(settingsPage)
}

private func settingsRows(_ settingsPage: SettingsPage) -> [SettingsEntry] {
    switch settingsPage {
    case .general:
        return page(.general, "menu-bar", "Menu bar", [
            ("icon-style", "Icon style", "What the icon in the menu bar shows"), ("animate-the-icon", "Animate the icon", "A segment moves over the bar while epics run"),
            ("list-epics-in-the-menu", "List epics in the menu", "The epics that run or wait show under the status"),
        ]) + page(.general, "display", "Display", [
            ("time-format", "Time format", "Ages read \"11m\" or as a time, \"14:32\""), ("clock", "Clock", "How clock times count the hours"),
        ])
    case .providers:
        return page(.providers, "accounts-that-need-attention", "Accounts that need attention", [("accounts-that-need-attention", "Accounts that need attention", "Signed out, or near the limit of the 5h window")])
            + page(.providers, "ai-providers", "AI providers", [("ai-providers", "AI providers", "The tools of this Mac, each with its accounts")])
            + page(.providers, "local-servers", "Local servers", [("local-servers", "Local servers", "LM Studio and Ollama, and the models they have loaded")])
            + page(.providers, "text-generators", "Text generators", [
                ("text-generators", "Text generators", "The local model that writes text for Carrier, chosen from LM Studio or Ollama"),
                ("titles-of-earlier-sessions", "Titles of earlier sessions", "Sessions whose title is still their first line"),
            ])
    case .appearance:
        return page(.appearance, "theme", "Theme", [("theme", "Theme", "Nine themes, each in light and dark")])
            + page(.appearance, "look", "Look", [
                ("color-scheme", "Color scheme", "System follows the Mac"), ("text-size", "Text size", "The size of the text of the interface; the messages have their own in Chat"), ("icon-set", "Icon set", "SF Symbols, Tabler or Lucide for the icons of the app"), ("icon-weight", "Icon weight", "How thick the strokes of the icons are"),
                ("density", "Density", "The space in the sidebar rows"), ("tell-states-apart-by-shape", "Tell states apart by shape", "A symbol in each state, so that color is not the only clue"),
            ]) + page(.appearance, "color", "Color", [
                ("accent-color", "Accent color", "Buttons, switches and the selection"), ("tint-the-windows", "Tint the windows", "A touch of the theme's own color on the backgrounds"),
                ("translucent-windows", "Translucent windows", "Off draws solid backgrounds"),
            ]) + page(.appearance, "code-and-output", "Code and output", [
                ("font", "Font", "The monospaced fonts installed on this Mac"), ("size", "Size", "In points, before the text size of the whole app"),
                ("line-height", "Line height", "The room between the lines of code and output"), ("ligatures", "Ligatures", "Joins pairs such as != and >= where the font has them"),
                ("wrap-long-lines", "Wrap long lines", "Off keeps each line whole and scrolls sideways"), ("line-numbers", "Line numbers", "In code blocks and the output of a command"),
            ])
    case .notifications:
        return page(.notifications, "carrier", "Carrier", [
            ("needs-attention", "Needs attention", "An epic stopped and waits for a person"), ("ready-for-test", "Ready for test", "An epic finished and has a PR to try"),
            ("a-problem", "A problem", "GitHub refuses a repo, or Carrier stops by itself"),
        ]) + page(.notifications, "chat", "Chat", [("needs-attention", "Needs attention", "A session waits for an approval"), ("done", "Done", "A session finished its turn")])
            + page(.notifications, "delivery", "Delivery", [
                ("only-when-carrier-is-not-in-front", "Only when Carrier is not in front", "No banner while its window is the one you are looking at"),
                ("dock-badge", "Dock badge", "The Dock icon counts what needs a person"), ("play-a-sound", "Play a sound", "A banner plays the notification sound"),
                ("remind-me-again", "Remind me again", "While something still needs attention"), ("quiet-hours", "Quiet hours", "Notifications wait in the Notification Center"),
                ("from", "From", "When the quiet starts"), ("until", "Until", "When it ends"),
            ]) + page(.notifications, "permission", "Permission", [("system-permission", "System permission", "Whether macOS lets Carrier send notifications")])
    case .keybindings:
        return ShortcutGroup.allCases.flatMap { group in
            page(.keybindings, group.rawValue, group.title, ShortcutCommand.allCases.filter { $0.group == group }.map { ($0.rawValue, $0.title, "Default: \($0.defaultCombo?.text ?? "none")") })
        }
    case .dictation:
        // the rest of this index is still English words (its own step gives them keys), so the screens' titles stay English with them
        let english = Copy.bundle("en"), englishLocale = Locale(identifier: "en_US")
        func screen(_ screen: DictationScreen, _ groupID: String, _ group: String, _ rows: [(id: String, title: String, detail: String)]) -> [SettingsEntry] {
            page(.dictation, groupID, group, rows, path: [screen.rawValue])
        }
        // the rows of the first screen that open a screen are the way to it from a search
        let opens = DictationScreen.allCases.map { screen in
            let yours = screen == .history || screen == .statistics
            return SettingsEntry(page: .dictation, groupID: yours ? "your-dictations" : "set-up", group: yours ? "Your dictations" : "Set up", rowID: screen.rawValue, title: screen.title(bundle: english, locale: englishLocale), detail: screen.detail(bundle: english, locale: englishLocale), path: [screen.rawValue])
        }
        return opens + page(.dictation, "dictation", "Dictation", [("microphone", "Microphone", "Whether Carrier may listen, in the card at the top")])
            + screen(.recognition, "speech-models", "Speech models", [("speech-models", "Speech models", "The models you can download, choose and delete")])
            + screen(.recognition, "", "", [("language", "Language", "What you speak")])
            + screen(.recognition, "memory", "Memory", [
                ("keep-the-speech-model-ready", "Keep the speech model ready", "Loads it when Carrier opens, so the first dictation does not wait"),
                ("release-the-model-after", "Release the model after", "Without dictating, to give its memory back"),
            ])
            + screen(.recognition, "storage", "Storage", [("downloaded-models", "Downloaded models", "How much space the models take")])
            + screen(.global, "global-dictation", "Global dictation", [
                ("dictate-in-any-app", "Dictate in any app", "Opens a widget in any app, and pastes what you say"), ("accessibility", "Accessibility", "What lets Carrier paste into another app"),
                ("shortcut", "Shortcut", "With Carrier in front on a session it dictates into the message box"), ("activation", "Activation", "Toggle, or hold the keys while you speak"),
            ])
            + screen(.global, "widget", "Widget", [
        ("widget-style", "Widget style", "Pill, Small, Medium or Large"), ("widget-theme", "Widget theme", "Default, Black, Dark glass, Clear glass or Theme glow"),
        ("live-text", "Live text", "Show the words as you say them, or only the time and the keys"),
        ("position", "Position", "Top or bottom centre, or where you dragged the widget"),
    ])
            + screen(.cleanup, "cleanup", "Cleanup", [
                ("clean-the-text-with-a-model", "Clean the text with a model", "Runs on this Mac; nothing leaves it"), ("server", "Server", "Where the local model runs"),
                ("model", "Model", "The model that cleans the text"), ("prompt", "Prompt", "What you ask the model to do with every dictation"), ("try-it", "Try it", "Runs the prompt on a sample"),
            ])
            + screen(.sounds, "sounds", "Sounds", [("start-sound", "Start sound", "Plays when it begins to listen"), ("end-sound", "End sound", "Plays when it stops listening"), ("volume", "Volume", "For both sounds, in the global dictation only")])
            + screen(.history, "history", "History", [
                ("keep-the-text-of-my-dictations", "Keep the text of my dictations", "A list with search, copy and delete, on this Mac"), ("keep-the-audio", "Keep the audio", "Each recorded dictation has its audio to play back"),
                ("delete-audio-older-than", "Delete audio older than", "The transcripts stay"), ("audio-on-disk", "Audio on disk", "How much space the audio takes"),
            ])
            + screen(.statistics, "overview", "Overview", [("overview", "Overview", "Dictations, words, speaking time and time saved, by range")])
            + screen(.statistics, "by-hour-of-the-day", "By hour of the day", [("by-hour-of-the-day", "By hour of the day", "When you dictate most")])
            + screen(.statistics, "this-week", "This week", [("this-week", "This week", "The last 7 days against the 7 before")])
            + screen(.statistics, "records", "Records", [("records", "Records", "Your best day, your longest dictation and your longest streak")])
            + screen(.statistics, "statistics-settings", "Statistics settings", [("typing-speed", "Typing speed", "Used for the time saved"), ("reset-statistics", "Reset statistics", "Deletes the counters; the history stays")])
    case .keepAwake:
        return page(.keepAwake, "now", "Now", [("now", "Now", "Whether the Mac is being kept awake, and the button that turns it on or off")])
            + page(.keepAwake, "by-hand", "By hand", [
                ("length", "Length", "What the menu's Keep awake item and the shortcut start"), ("keep-the-screen-on", "Keep the screen on", "Off lets the screen sleep while the Mac stays awake"),
                ("shortcut", "Shortcut", "Turns keep awake on or off from any app"),
            ])
            + page(.keepAwake, "with-agents", "With agents", [
                ("keep-awake-while-agents-work", "Keep awake while agents work", "While an epic runs or a session works"), ("stay-awake-after-they-finish", "Stay awake after they finish", "Time to read the result before the Mac may sleep"),
            ])
            + page(.keepAwake, "battery-and-notices", "Battery and notices", [
                ("on-battery", "On battery", "What it does when the Mac runs on battery"), ("tell-me-when-it-stops-by-itself", "Tell me when it stops by itself", "A notification when the time runs out or the battery ends it"),
            ])
    case .chat:
        return page(.chat, "message-box", "Message box", [
            ("send-with", "Send with", "The other key makes a new line"), ("while-the-agent-works", "While the agent works", "Hold the message, or stop the turn and send it"),
            ("writing-tools", "Writing Tools", "The system's offer to rewrite or proofread what you select"), ("check-spelling", "Check spelling", "Underline words that look misspelled"),
            ("correct-spelling-automatically", "Correct spelling automatically", "Fix a misspelled word as you type it"),
            ("context-and-limits", "Context and limits", "A ring beside the microphone: how full the context is and how much of the 5h limit is used"),
        ]) + page(.chat, "conversation", "Conversation", [
            ("follow-new-output", "Follow new output", "Scroll to what arrives while you are at the end"), ("message-times", "Message times", "When a message shows the time it was written"),
            ("tool-output", "Tool output", "Nothing, each run folded, or every call open"), ("open-the-calls-that-failed", "Open the calls that failed", "A call that failed opens by itself"),
            ("diff-style", "Diff style", "Unified, or removed and added side by side"), ("output-length", "Output length", "How many lines of an output show before Show more"),
            ("show-reasoning", "Show reasoning", "The agent's reasoning, folded under its message"), ("message-width", "Message width", "How wide a message gets before it wraps"), ("message-text-size", "Message text size", "The size of the font of the messages, apart from the app's text size"),
            ("line-spacing", "Line spacing", "The room between the lines of a message (line height)"), ("message-spacing", "Message spacing", "The room between the messages"),
            ("surfaces", "Surfaces", "Glass blurs what is under; flat is a quiet solid fill"),
        ])
    case .sessions:
        return page(.sessions, "new-sessions", "New sessions", [("starts-with", "Starts with", "Provider, model and reasoning"), ("work-in", "Work in", "Base folder or a new worktree"),
            ("start-from", "Start from", "Where a new worktree is cut: the remote branch (latest) or the local branch")])
            + page(.sessions, "idle-sessions", "Idle sessions", [
                ("sleep-after", "Sleep after", "How long an idle session nobody opens keeps its agent running before it closes and falls asleep, freeing its memory (the timeout of an inactive session, or inactivity timeout): 10 minutes, 30 minutes or 1 hour"),
            ]) + page(.sessions, "archive-and-delete", "Archive and delete", [
                ("archive-after", "Archive after", "Days without activity before it is archived"), ("delete-after", "Delete after", "Days an archived session waits before it is deleted"),
                ("ask-before-deleting-a-session", "Ask before deleting a session", "The question says its worktree goes with it"),
            ]) + page(.sessions, "with-these-ages", "With these ages", [("with-these-ages", "With these ages", "What the ages do to a session left alone from today")])
    case .projects:
        // the list and each project's screen are per-project, so their rows are not statically indexed: the page is found by its name and its line
        return []
    case .sidebar:
        return page(.sidebar, "order", "Order", [
            ("group-epics-by", "Group epics by", "How the epics under Carrier are grouped"), ("sort-sessions", "Sort sessions", "How the Sessions list is grouped and ordered"),
            ("sort-the-archive", "Sort the Archive", "How the archived sessions are ordered"),
        ]) + page(.sidebar, "session-rows", "Session rows", [
            ("project-icon", "Project icon", "The colored square with the project's initials"), ("branch", "Branch", "Where the session works, the branch or the base folder"),
            ("pull-request", "Pull request", "The pull request of the session's branch, with its state and checks"), ("lines-changed", "Lines changed", "How many lines the session added and removed"),
            ("providers", "Providers", "The marks of the providers the session used"), ("age", "Age", "How long ago the session was last active"),
        ])
    case .terminal:
        return page(.terminal, "appearance", "Appearance", [
            ("theme", "Theme", "Color palette for panes; inherits the app theme by default"), ("minimum-contrast", "Minimum contrast", "Raises low-contrast ANSI text"),
            ("horizontal-padding", "Horizontal padding", "Left and right margin inside each pane"), ("vertical-padding", "Vertical padding", "Top and bottom margin inside each pane"),
        ]) + page(.terminal, "typography", "Typography", [
            ("font", "Font", "Monospaced font used in panes; inherits Appearance › Code and output"), ("size", "Size", "Text size in points for terminal output"),
            ("ligatures", "Ligatures", "Joins pairs such as != and >= where the font has them"), ("thicken-font", "Thicken font", "Renders glyphs slightly heavier on Retina displays"),
        ]) + page(.terminal, "cursor", "Cursor", [("cursor-style", "Cursor style", "Shape of the text cursor inside terminal panes"), ("blink-cursor", "Blink cursor", "Animates the cursor when the pane is focused")])
            + page(.terminal, "panes", "Panes", [
                ("dim-inactive-panes", "Dim inactive panes", "Softens unfocused split panes so the active pane stands out"),
                ("focus-follows-mouse", "Focus follows mouse", "Activates split panes when hovering over them without clicking"),
            ]) + page(.terminal, "input-and-scrollback", "Input and scrollback", [
                ("option-as-alt", "Option as Alt", "Sends Option key presses as Meta/Alt escape sequences in shells"),
                ("copy-on-select", "Copy on select", "Copies highlighted terminal text to the clipboard automatically"), ("scrollback-limit", "Scrollback limit", "Memory reserved per pane for scrollback output history"),
            ]) + page(.terminal, "shell-and-closing", "Shell and closing", [
                ("pin-zsh-prompt-to-bottom", "Pin Zsh prompt to bottom", "Keeps new interactive prompts at the bottom row without changing dotfiles"),
                ("confirm-before-closing-running-commands", "Confirm before closing running commands", "Asks before closing a tab, split, or drawer with an active process"),
            ])
    case .agents:
        // the rows of a role's screen are the same for the three roles: the search opens the Author's, and the Lead reviewer's switch opens its own
        let role = [AgentRole.author.rawValue]
        var entries = page(.agents, "how-an-epic-runs", "How an epic runs", AgentRole.allCases.map { ($0.rawValue, $0.title, $0.purpose) })
        entries += page(.agents, "identities", "Identities", [("create-a-bot", "Create a bot…", "Opens Terminal on agent-forge add, to make a GitHub identity for a role")])
        entries += page(.agents, "", "", [("use-a-lead-reviewer", "Use a lead reviewer", "A second reviewer checks the first")], path: [AgentRole.leadReviewer.rawValue])
        entries += page(.agents, "who", "Who", [("identity", "Identity", "The GitHub identity an agent acts as"), ("model", "Model", "The model and reasoning of the role")], path: role)
        entries += page(.agents, "persona", "Persona", [("persona-name", "Persona name", "Optional, one line up to 40 characters"), ("persona-prompt", "Persona prompt", "Optional instructions")], path: role)
        for skillRole in AgentRole.allCases {
            var rows = skillRole.stages.map { ($0.id, $0.title, "\($0.detail). Runs the skill \($0.skill)") }
            if skillRole.stages.isEmpty { rows.append(("not-used-by-the-engine-yet", "Not used by the engine yet", "The Lead reviewer has no stage, so no skill")) }
            entries += page(.agents, "skills", "Skills", rows, path: [skillRole.rawValue])
        }
        entries += page(.agents, "when-it-runs-out-of-tokens", "When it runs out of tokens", [("switch-automatically", "Switch automatically", "Usage limit, rate limit or service down")], path: role)
        return entries
    case .watching:
        return page(.watching, "repositories", "Repositories", [("repositories", "Repositories", "The repositories Carrier takes epics from")])
            + page(.watching, "status", "Status", [("epics", "Epics", "What the repository has in flight"), ("last-check", "Last check", "When Carrier last looked at the repository, or why GitHub refused it")])
            + page(.watching, "ready-for-carrier", "Ready for Carrier", [("ready-for-carrier", "Ready for Carrier", "Whether Carrier can read the repository, sign for it and has the Solve labels")])
            + page(.watching, "who-works-here", "Who works here", [("who-works-here", "Who works here", "Each role of the repository, and what it sets of its own")])
            + page(.watching, "repository", "Repository", [
                ("project", "Project", "The project that has this repository as its origin"), ("clone", "Clone", "Where Carrier keeps its own clone of the repository"), ("on-github", "On GitHub", "The repository's address"),
            ])
            + page(.watching, "stop-watching", "Stop watching", [("stop-watching", "Stop watching", "Its epics stop where they are; nothing is deleted")])
    case .behavior:
        return behaviorGroups.flatMap { group in page(.behavior, group.id, group.title, group.rows.map { ($0.key, $0.title, $0.detail) }) }
    case .engine:
        return page(.engine, "starting", "Starting", [
            ("startOnOpen", "Start Carrier when the app opens", "Carrier starts working on ready epics as soon as the app opens"),
            ("confirmStop", "Ask before stopping Carrier", "Only when stopping would interrupt epics that are running"),
        ]) + page(.engine, "programs", "Programs", [
            ("carrier", "carrier", "The program the app runs"), ("node", "node", "What runs it"), ("path", "PATH", "Where the app looks for tools"),
            ("lookAgain", "Look for the tools again", "Looks for carrier and node again"),
        ]) + page(.engine, "github-identity", "GitHub identity", [("orchestratorProfile", "Carrier acts on GitHub as", "Reads issues and PRs and changes labels")])
            + page(.engine, "files", "Files", [
                ("carrierFolder", "Carrier folder", "Where Carrier keeps its config, clones and logs"), ("logs", "Logs", "What Carrier wrote while it ran"),
                ("startLog", "Start log", "What the app saw the last time it started Carrier"),
            ])
    case .health:
        return page(.health, "this-mac", "This Mac", [("this-mac", "This Mac", "The tools the chat needs: git, gh and your AI providers")])
            + page(.health, "carrier", "Carrier", [("chat-host", "Chat host", "Whether the chat host runs"), ("engine", "Engine", "Whether the engine runs")])
            + page(.health, "engine-setup", "Engine setup", [("engine-setup", "Engine setup", "What carrier doctor says about the setup of the engine")])
    case .about:
        return page(.about, "about", "About", [("star-carrier-on-github", "Star Carrier on GitHub", "A star helps other people find it")])
            + page(.about, "updates", "Updates", [
                ("check-by-itself", "Check by itself", "Looks for a newer Carrier when it opens and from time to time"),
                ("install-by-itself", "Install by itself", "Installs when you quit; off, it asks before it installs"), ("update-delay", "Update delay", "Waits this long after a release before offering it"),
            ]) + page(.about, "engine", "Engine", [("engine-and-chat-host", "Engine and chat host", "The engine's own update")])
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
        let title = fold(entry.title), place = fold(entry.group + " " + entry.page.title), detail = fold(entry.detail)
        guard words.allSatisfy({ title.contains($0) || place.contains($0) || detail.contains($0) }) else { return nil }
        if words.allSatisfy({ title.contains($0) }) { return 0 }
        if words.allSatisfy({ title.contains($0) || place.contains($0) }) { return 1 }
        return 2
    }
    return entries.enumerated().compactMap { index, entry in rank(entry).map { (rank: $0, index: index, entry: entry) } }
        .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.map(\.entry)
}
