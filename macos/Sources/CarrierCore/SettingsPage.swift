/// A page of the Settings rail: its title is the raw value, and it carries its group and its row of the rail. The rail is built from
/// these, in the order of the cases.
public enum SettingsPage: String, CaseIterable {
    case general = "General", notifications = "Notifications", appearance = "Appearance", sidebar = "Sidebar", chat = "Chat"
    case keybindings = "Keybindings"
    case providers = "Providers"
    case repos = "Repos"
    case engine = "Engine", behavior = "Behavior", sessions = "Sessions", health = "Health"

    /// A group of the rail: the App and Providers ones have no heading, Carrier and Legacy have their own.
    public enum Group: CaseIterable {
        case app, providers, carrier, legacy

        public var heading: String? {
            switch self {
            case .app, .providers: nil
            case .carrier: "Carrier"
            case .legacy: "Legacy"
            }
        }
    }

    public var group: Group {
        switch self {
        case .general, .notifications, .appearance, .sidebar, .chat, .keybindings: .app
        case .providers: .providers
        case .repos: .carrier
        case .engine, .behavior, .sessions, .health: .legacy
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
        case .keybindings: "keyboard"
        case .providers: "brain"
        case .engine: "cpu"
        case .behavior: "slider.horizontal.3"
        case .repos: "tray.full"
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
        case .keybindings: "The keys that run the app's actions"
        case .providers: "The AI tools on this Mac and their accounts"
        case .engine: "How the app starts Carrier"
        case .behavior: "How epics run"
        case .repos: "What Carrier watches"
        case .sessions: "When sessions age out"
        case .health: "Is this Mac ready?"
        }
    }

    public static func pages(in group: Group) -> [SettingsPage] { allCases.filter { $0.group == group } }
}
