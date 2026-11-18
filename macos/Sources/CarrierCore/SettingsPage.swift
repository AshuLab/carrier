/// A page of Settings: its title is the raw value, and it carries its group and its row of the sidebar. The sidebar is built from these, in
/// the order of the cases.
public enum SettingsPage: String, CaseIterable, Sendable {
    case general = "General", providers = "Providers", appearance = "Appearance", notifications = "Notifications"
    case keybindings = "Keybindings", dictation = "Dictation"
    case chat = "Chat", sessions = "Sessions", sidebar = "Sidebar", terminal = "Terminal"
    case agents = "Agents", repos = "Repos", behavior = "Behavior"
    case engine = "Engine", health = "Health", about = "About"

    /// A group of the sidebar: the App one has no heading, the others have their own.
    public enum Group: CaseIterable, Sendable {
        case app, workspace, carrier, system

        public var heading: String? {
            switch self {
            case .app: nil
            case .workspace: "Workspace"
            case .carrier: "Carrier"
            case .system: "System"
            }
        }
    }

    public var group: Group {
        switch self {
        case .general, .providers, .appearance, .notifications, .keybindings, .dictation: .app
        case .chat, .sessions, .sidebar, .terminal: .workspace
        case .agents, .repos, .behavior: .carrier
        case .engine, .health, .about: .system
        }
    }

    /// The page is a native `Form` of grouped sections. The others (accounts, the repos, the checks and the speech models) are lists and tables
    /// of their own, which a form would not hold.
    public var usesForm: Bool {
        switch self {
        case .general, .appearance, .notifications, .keybindings, .chat, .sessions, .sidebar, .terminal, .agents, .behavior, .engine, .about: true
        case .providers, .dictation, .repos, .health: false
        }
    }

    /// The page is a column of the same width as the others (a readable line, centered). The lists that open an editor, the checks and the
    /// tables take the whole width of the window instead.
    public var isColumn: Bool {
        switch self {
        case .providers, .repos, .health, .dictation: false
        default: true
        }
    }

    /// The page's icon in the sidebar (an SF Symbol).
    public var icon: String {
        switch self {
        case .general: "gearshape"
        case .notifications: "bell"
        case .appearance: "paintbrush"
        case .terminal: "terminal"
        case .sidebar: "sidebar.left"
        case .chat: "bubble.left.and.text.bubble.right"
        case .dictation: "mic"
        case .keybindings: "keyboard"
        case .about: "info.circle"
        case .providers: "brain"
        case .engine: "cpu"
        case .behavior: "slider.horizontal.3"
        case .repos: "tray.full"
        case .agents: "person.2"
        case .sessions: "clock.arrow.circlepath"
        case .health: "stethoscope"
        }
    }

    /// The line under the title.
    public var detail: String {
        switch self {
        case .general: "The menu bar and how times read"
        case .notifications: "What to tell you"
        case .appearance: "Theme, color, text size, density and the font of code"
        case .terminal: "Theme, font, cursor, padding and shell behavior"
        case .sidebar: "What the sessions list shows"
        case .chat: "The message box and the conversation"
        case .dictation: "Speak instead of typing"
        case .keybindings: "The keys that run the app's actions"
        case .about: "This version, its links and whether Carrier updates by itself"
        case .providers: "The AI tools on this Mac and their accounts"
        case .engine: "How the app runs Carrier"
        case .behavior: "How Carrier runs epics"
        case .repos: "What Carrier watches"
        case .agents: "Who works on an epic and where it goes when its tokens run out"
        case .sessions: "How sessions start and age out"
        case .health: "Is this Mac ready?"
        }
    }

    public static func pages(in group: Group) -> [SettingsPage] { allCases.filter { $0.group == group } }
}
