/// A page of Settings: its title is the raw value, and it carries its group and its row of the sidebar. The sidebar is built from these, in
/// the order of the cases.
public enum SettingsPage: String, CaseIterable, Sendable {
    case general = "General", providers = "Providers", appearance = "Appearance", notifications = "Notifications"
    case keybindings = "Keybindings", dictation = "Dictation", keepAwake = "Keep awake"
    case chat = "Chat", sessions = "Sessions", projects = "Projects", sidebar = "Sidebar", terminal = "Terminal"
    case agents = "Agents", watching = "Watching", behavior = "Behavior"
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
        case .general, .providers, .appearance, .notifications, .keybindings, .dictation, .keepAwake: .app
        case .chat, .sessions, .projects, .sidebar, .terminal: .workspace
        case .agents, .watching, .behavior: .carrier
        case .engine, .health, .about: .system
        }
    }

    /// The page is a native `Form` of grouped sections. The others (the projects and the checks) are lists and tables of their own, which a form
    /// would not hold.
    public var usesForm: Bool {
        switch self {
        case .general, .providers, .appearance, .notifications, .keybindings, .dictation, .keepAwake, .chat, .sessions, .sidebar, .terminal, .agents, .watching, .behavior, .engine, .about: true
        case .projects, .health: false
        }
    }

    /// The page is a column of the same width as the others (a readable line, centered). The list of projects and the checks take the whole
    /// width of the window instead (a project's own screen is a column: `SettingsPlace.isColumn`).
    public var isColumn: Bool {
        switch self {
        case .projects, .health: false
        default: true
        }
    }

    /// The page's icon in the sidebar.
    public var icon: AppIcon {
        switch self {
        case .general: .settings
        case .notifications: .bell
        case .appearance: .brush
        case .terminal: .terminal
        case .sidebar: .sidebar
        case .chat: .messages
        case .dictation: .microphone
        case .keybindings: .keyboard
        case .keepAwake: .cup
        case .about: .info
        case .providers: .brain
        case .engine: .cpu
        case .behavior: .sliders
        case .watching: .inbox
        case .agents: .users
        case .sessions: .history
        case .projects: .folder
        case .health: .stethoscope
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
        case .keepAwake: "Keep the Mac from sleeping, by hand or while agents work"
        case .about: "This version, its links and whether Carrier updates by itself"
        case .providers: "The AI providers on this Mac and their accounts"
        case .engine: "How the app runs Carrier"
        case .behavior: "How Carrier runs epics"
        case .watching: "The repositories Carrier takes epics from"
        case .agents: "Who works on an epic and where it goes when its tokens run out"
        case .sessions: "How sessions start and age out"
        case .projects: "The folders you work in"
        case .health: "Is this Mac ready?"
        }
    }

    public static func pages(in group: Group) -> [SettingsPage] { allCases.filter { $0.group == group } }
}
