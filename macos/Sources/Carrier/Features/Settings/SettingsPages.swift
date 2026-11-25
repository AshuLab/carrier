import AppKit
import CarrierCore
import SwiftUI

// The detail of the Settings window: the chosen page in a scroll of its own.

/// How wide the pages of rows are, whatever the window: the same for every page that is a column (`SettingsPage.isColumn`).
let settingsColumnWidth: CGFloat = 760

/// The chosen page in a scroll of its own; its title is the window's toolbar. The readiness banner shows over every page while something is
/// missing or being looked for.
struct SettingsPages: View {
    let state: ConnectionState?
    let canReload: Bool
    var sessions: [SessionRow] = []
    let navigator: SettingsNavigator
    /// The place the search chose: scrolled to and shown for a moment, once the page is drawn.
    @Binding var target: SettingsEntry?
    @Binding var headerNote: SettingsHeaderNote?
    /// What a screen of a page says of itself in the toolbar (a provider's name, an account's), when it is not the page's.
    @Binding var title: SettingsTitle?
    @ObservedObject var setup: SetupController = .shared
    @State private var highlight: String?
    /// The width the page has, to center a column in it.
    @State private var width: CGFloat = 0
    private var page: SettingsPage { navigator.page }
    private var inset: CGFloat { navigator.place.isColumn ? max(0, (width - settingsColumnWidth) / 2) : 0 }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if page.usesForm {
                    // the form scrolls by itself; what is said over every page of its own kind stays above it
                    VStack(spacing: Tokens.Space.none) {
                        notices.padding(.horizontal, Tokens.Space.s24 + inset).padding(.top, showsNotices ? Tokens.Space.s24 : Tokens.Space.none).padding(.bottom, showsNotices ? Tokens.Space.s8 : Tokens.Space.none)
                        pageContent
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Tokens.Space.s14) {
                            notices
                            pageContent
                        }
                        .padding(Tokens.Space.s24).frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            // a page that is a column is centered by margins of its scroll view, not by narrowing the view: the scroll bar stays at the edge of the
            // window and what scrolls under the toolbar reaches both sides of it
            .contentMargins(.horizontal, inset, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
            .environment(\.settingsForm, page.usesForm)
            // the theme's color under the page, as under the main window's views
            .themedWindowBackground()
            .id(page)
            // the page is drawn a moment after it is chosen: scroll to the place, show it, and let it go
            .task(id: target?.id) {
                guard let place = target, place.page == page else { return }
                try? await Task.sleep(for: .milliseconds(200))
                withAnimation { proxy.scrollTo(place.anchor, anchor: .center) }
                highlight = place.anchor
                try? await Task.sleep(for: .seconds(1.8))
                highlight = nil
                target = nil
            }
        }
        .environment(\.settingsPage, page)
        .environment(\.settingsHighlight, highlight)
        .onPreferenceChange(SettingsHeaderNoteKey.self) { headerNote = $0 }
        .onPreferenceChange(SettingsTitleKey.self) { title = $0 }
    }

    /// The readiness banner and what detecting said belong to the pages where it is fixed, not to every page.
    private var showsNotices: Bool { (page == .engine || page == .health) && (banner.state != .ready || setup.message != nil) }
    private var banner: ReadinessBanner { readinessBanner(missing: setup.missing, detecting: setup.detecting) }

    @ViewBuilder private var notices: some View {
        if showsNotices {
            VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                if banner.state != .ready {
                    ReadinessBannerView(banner: banner, detecting: setup.detecting) { setup.detect() }
                }
                if let message = setup.message {
                    Label(message, icon: .warningFilled).scaledFont(12).foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .general: GeneralTabView()
        case .appearance: AppearanceTabView()
        case .terminal: TerminalTabView()
        case .sidebar: SidebarTabView()
        case .chat: ChatTabView()
        case .dictation: DictationTabView(place: navigator.place, go: navigator.go)
        case .keybindings: KeybindingsTabView()
        case .keepAwake: KeepAwakeTabView()
        case .about: AboutTabView(updater: AppUpdater.shared)
        case .providers: ProvidersTabView(place: navigator.place, go: navigator.go, back: navigator.back, openAgents: { navigator.go(.agents) })
        case .engine: EngineTabView(setup: setup)
        case .behavior: BehaviorTabView()
        case .watching: WatchingTabView(place: navigator.place, go: navigator.go, state: state, canReload: canReload, openAgents: { navigator.go(.agents) })
        case .agents: AgentsTabView(place: navigator.place, go: navigator.go)
        case .sessions: SessionsTabView()
        case .projects: ProjectsTabView(place: navigator.place, go: navigator.go, sessions: sessions, state: state, canReload: canReload)
        case .notifications: NotificationsTabView(centre: SystemNotificationCentre.shared, reader: SystemNotificationCentre.shared)
        case .health: HealthTabView(state: state)
        }
    }
}
