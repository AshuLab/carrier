/// A page of the Settings rail: its title is the raw value, and it carries its group and its row of the rail. The rail is built from
/// these, in the order of the cases.
public enum SettingsPage: String, CaseIterable {
    case general = "General", providers = "Providers", notifications = "Notifications", appearance = "Appearance", terminal = "Terminal"
    case keybindings = "Keybindings", dictation = "Dictation", keepAwake = "Keep awake"
    case chat = "Chat", sidebar = "Sidebar", sessions = "Sessions"
    case repos = "Repos"
    case agents = "Agents"
    case behavior = "Behavior"
    case engine = "Engine"
    case health = "Health"
    case about = "About"

    /// A group of the rail: the App one has no heading, Chat and Carrier have their own, and About is last, kept at the foot of the rail.
    public enum Group: CaseIterable {
        case app, chat, carrier, about

        public var heading: String? {
            switch self {
            case .app: nil
            case .chat: "Chat"
            case .carrier: "Carrier"
            case .about: nil
            }
        }
    }

    public var group: Group {
        switch self {
        case .general, .providers, .notifications, .appearance, .terminal, .keybindings, .dictation, .keepAwake: .app
        case .chat, .sidebar, .sessions: .chat
        case .repos, .agents, .behavior, .engine, .health: .carrier
        case .about: .about
        }
    }

    /// The page's icon in the rail and in its header (an SF Symbol).
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
        case .keepAwake: "cup.and.saucer"
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
        case .keepAwake: "Keep the Mac from sleeping, by hand or while agents work"
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
