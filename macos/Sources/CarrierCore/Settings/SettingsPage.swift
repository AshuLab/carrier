import Foundation

/// A page of Settings: its raw value is its identifier (what an anchor and the remembered page are made of, never shown), and it carries its
/// title, its group and its row of the sidebar. The sidebar is built from these, in the order of the cases.
public enum SettingsPage: String, CaseIterable, Sendable {
    case general, providers, appearance, notifications, keybindings, dictation, keepAwake = "keep-awake"
    case chat, sessions, projects, sidebar, terminal
    case agents, watching, behavior
    case engine, health, about

    /// The page for what was stored as the last page: its identifier, or the English title an earlier build stored; General for anything else.
    public init(stored value: String) {
        let english = Copy.bundle("en"), locale = Locale(identifier: "en_US")
        self = Self(rawValue: value) ?? Self.allCases.first { $0.title(bundle: english, locale: locale) == value } ?? .general
    }

    /// The page's name, as the sidebar, the results of a search and the window's title show it.
    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .general: Copy.settingsPageGeneral(bundle: bundle, locale: locale)
        case .providers: Copy.settingsPageProviders(bundle: bundle, locale: locale)
        case .appearance: Copy.settingsPageAppearance(bundle: bundle, locale: locale)
        case .notifications: Copy.settingsPageNotifications(bundle: bundle, locale: locale)
        case .keybindings: Copy.settingsPageKeybindings(bundle: bundle, locale: locale)
        case .dictation: Copy.settingsPageDictation(bundle: bundle, locale: locale)
        case .keepAwake: Copy.settingsPageKeepAwake(bundle: bundle, locale: locale)
        case .chat: Copy.settingsPageChat(bundle: bundle, locale: locale)
        case .sessions: Copy.settingsPageSessions(bundle: bundle, locale: locale)
        case .projects: Copy.settingsPageProjects(bundle: bundle, locale: locale)
        case .sidebar: Copy.settingsPageSidebar(bundle: bundle, locale: locale)
        case .terminal: Copy.settingsPageTerminal(bundle: bundle, locale: locale)
        case .agents: Copy.settingsPageAgents(bundle: bundle, locale: locale)
        case .watching: Copy.settingsPageWatching(bundle: bundle, locale: locale)
        case .behavior: Copy.settingsPageBehavior(bundle: bundle, locale: locale)
        case .engine: Copy.settingsPageEngine(bundle: bundle, locale: locale)
        case .health: Copy.settingsPageHealth(bundle: bundle, locale: locale)
        case .about: Copy.settingsPageAbout(bundle: bundle, locale: locale)
        }
    }

    /// A group of the sidebar: the App one has no heading, the others have their own.
    public enum Group: CaseIterable, Sendable {
        case app, workspace, carrier, system

        public func heading(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
            switch self {
            case .app: nil
            case .workspace: Copy.settingsGroupWorkspace(bundle: bundle, locale: locale)
            case .carrier: Copy.settingsGroupCarrier(bundle: bundle, locale: locale)
            case .system: Copy.settingsGroupSystem(bundle: bundle, locale: locale)
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
    public func detail(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .general: Copy.settingsPageGeneralDetail(bundle: bundle, locale: locale)
        case .providers: Copy.settingsPageProvidersDetail(bundle: bundle, locale: locale)
        case .appearance: Copy.settingsPageAppearanceDetail(bundle: bundle, locale: locale)
        case .notifications: Copy.settingsPageNotificationsDetail(bundle: bundle, locale: locale)
        case .keybindings: Copy.settingsPageKeybindingsDetail(bundle: bundle, locale: locale)
        case .dictation: Copy.settingsPageDictationDetail(bundle: bundle, locale: locale)
        case .keepAwake: Copy.settingsPageKeepAwakeDetail(bundle: bundle, locale: locale)
        case .chat: Copy.settingsPageChatDetail(bundle: bundle, locale: locale)
        case .sessions: Copy.settingsPageSessionsDetail(bundle: bundle, locale: locale)
        case .projects: Copy.settingsPageProjectsDetail(bundle: bundle, locale: locale)
        case .sidebar: Copy.settingsPageSidebarDetail(bundle: bundle, locale: locale)
        case .terminal: Copy.settingsPageTerminalDetail(bundle: bundle, locale: locale)
        case .agents: Copy.settingsPageAgentsDetail(bundle: bundle, locale: locale)
        case .watching: Copy.settingsPageWatchingDetail(bundle: bundle, locale: locale)
        case .behavior: Copy.settingsPageBehaviorDetail(bundle: bundle, locale: locale)
        case .engine: Copy.settingsPageEngineDetail(bundle: bundle, locale: locale)
        case .health: Copy.settingsPageHealthDetail(bundle: bundle, locale: locale)
        case .about: Copy.settingsPageAboutDetail(bundle: bundle, locale: locale)
        }
    }

    public static func pages(in group: Group) -> [SettingsPage] { allCases.filter { $0.group == group } }
}
