/// A page of the Settings rail: its title is the raw value, and it carries its group and its row of the rail. The rail is built from
/// these, in the order of the cases.
public enum SettingsPage: String, CaseIterable {
    case general = "General", providers = "Providers", notifications = "Notifications", appearance = "Appearance"
    case keybindings = "Keybindings"
    case updates = "Updates"
    case chat = "Chat", sidebar = "Sidebar", sessions = "Sessions", dictation = "Dictation"
    case repos = "Repos"
    case agents = "Agents"
    case behavior = "Behavior"
    case engine = "Engine", health = "Health"

    /// A group of the rail: the App one has no heading, Chat, Carrier and Legacy have their own.
    public enum Group: CaseIterable {
        case app, chat, carrier, legacy

        public var heading: String? {
            switch self {
            case .app: nil
            case .chat: "Chat"
            case .carrier: "Carrier"
            case .legacy: "Legacy"
            }
        }
    }

    public var group: Group {
        switch self {
        case .general, .providers, .notifications, .appearance, .keybindings, .updates: .app
        case .chat, .sidebar, .sessions, .dictation: .chat
        case .repos, .agents, .behavior: .carrier
        case .engine, .health: .legacy
        }
    }

    /// The page's icon in the rail and in its header (an SF Symbol).
    public var icon: String {
        switch self {
        case .general: "gearshape"
        case .notifications: "bell"
        case .appearance: "paintbrush"
        case .sidebar: "sidebar.left"
        case .chat: "bubble.left.and.text.bubble.right"
        case .dictation: "mic"
        case .keybindings: "keyboard"
        case .updates: "arrow.down.circle"
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
        case .general: "The menu bar and the questions Carrier asks"
        case .notifications: "What to tell you"
        case .appearance: "Theme, color, text size, density and the font of code"
        case .sidebar: "What the sessions list shows"
        case .chat: "The message box and the conversation"
        case .dictation: "Speak instead of typing"
        case .keybindings: "The keys that run the app's actions"
        case .updates: "This version, and whether Carrier looks for a newer one by itself"
        case .providers: "The AI tools on this Mac and their accounts"
        case .engine: "How the app starts Carrier"
        case .behavior: "How Carrier runs epics"
        case .repos: "What Carrier watches"
        case .agents: "Who works on an epic and where it goes when its tokens run out"
        case .sessions: "How sessions start and age out"
        case .health: "Is this Mac ready?"
        }
    }

    public static func pages(in group: Group) -> [SettingsPage] { allCases.filter { $0.group == group } }
}
