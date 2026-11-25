import AppKit
import CarrierCore
import SwiftUI

// The detail of the Settings window: the chosen page in a scroll of its own, and the Engine page, which is drawn here.

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
    @ObservedObject private var start = StartController.shared
    @AppStorage(Preference.engineStartOnOpen) private var startOnOpen
    @AppStorage(Preference.stopConfirm) private var confirmStop
    @StateObject private var github = EngineIdentityStore()
    /// What `carrier --version` and `node --version` printed for the programs the page shows; nil while they are being read.
    @State private var versions: ProgramVersions?
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
                    Label(message, icon: .warningFilled).font(.scaled(12)).foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder private var pageContent: some View {
        let notConfigured = engineNotConfiguredNotice(configExists: start.configExists)
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
        case .engine:
            // one container, so the versions are read once and not once per group
            SettingsPageBody { engine(notConfigured: notConfigured) }
                .task(id: versionsKey) {
                    versions = nil
                    versions = await ProgramVersions.read(setup)
                }
        case .behavior: BehaviorTabView()
        case .watching: WatchingTabView(place: navigator.place, go: navigator.go, state: state, canReload: canReload, openAgents: { navigator.go(.agents) })
        case .agents: AgentsTabView(place: navigator.place, go: navigator.go)
        case .sessions: SessionsTabView()
        case .projects: ProjectsTabView(place: navigator.place, go: navigator.go, sessions: sessions, state: state, canReload: canReload)
        case .notifications: NotificationsTabView(centre: SystemNotificationCentre.shared, reader: SystemNotificationCentre.shared)
        case .health: HealthTabView(state: state)
        }
    }

    /// Changes when a program the page shows does, and when a detection ends (an upgrade keeps the path), so the versions are read again.
    private var versionsKey: String { "\(setup.carrier ?? "")|\(setup.settings.node)|\(setup.settings.path)|\(setup.detecting)" }

    @ViewBuilder private func engine(notConfigured: String?) -> some View {
        if let notConfigured {
            Label(notConfigured, icon: .warningFilled).font(.scaled(12)).foregroundStyle(.orange)
        }
        let programs = EnginePrograms(
            carrier: setup.carrier, carrierIsOwn: setup.carrierIsOwn, carrierVersion: versions?.carrier, setup: setup.settings, nodeVersion: versions?.node,
            carrierRuns: setup.carrierRuns, versionsRead: versions != nil
        )
        let folder = carrierFolder(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory())
        ForEach(
            engineGroups(
                configured: notConfigured == nil, programs: programs, identity: github.identity, identityFailure: github.failure, folder: folder,
                home: NSHomeDirectory(),
                exists: { FileManager.default.fileExists(atPath: $0) }
            ),
            id: \.title
        ) { group in
            SettingsGroup(id: group.id, title: group.title) {
                ForEach(Array(group.rows.enumerated()), id: \.element.title) { index, row in
                    SettingsTabRow(id: row.id.rawValue, title: row.title, detail: row.detail, first: index == 0, note: row.note ?? row.file?.shown, problem: row.problem) {
                        switch row.id {
                        case .startOnOpen: Toggle(row.title, isOn: $startOnOpen).labelsHidden().toggleStyle(.switch).disabled(notConfigured != nil)
                        case .confirmStop: Toggle(row.title, isOn: $confirmStop).labelsHidden().toggleStyle(.switch)
                        case .carrier: CarrierChoice(setup: setup, offersHomebrew: row.offersHomebrew)
                        case .node, .path: EmptyView()
                        case .lookAgain:
                            HStack(spacing: Tokens.Space.s8) {
                                // beside the button, so the button keeps its size and its name while it works
                                if setup.detecting { ProgressView().controlSize(.small).accessibilityLabel("Detecting") }
                                Button { setup.detect(); start.refreshConfig() } label: { Label("Detect", icon: .refresh).labelStyle(.titleAndIcon) }
                                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(setup.detecting)
                            }
                            .onChange(of: setup.detecting) { _, detecting in
                                if detecting == false { AccessibilityNotification.Announcement(setup.message ?? "Detection finished").post() }
                            }
                        case .orchestratorProfile: identityChoice(row.title)
                        case .carrierFolder, .logs, .startLog:
                            if let file = row.file {
                                Button {
                                    let url = URL(fileURLWithPath: file.path)
                                    if file.action == .reveal { NSWorkspace.shared.activateFileViewerSelecting([url]) } else { NSWorkspace.shared.open(url) }
                                } label: { Label(file.buttonTitle, icon: file.exists ? (file.action == .reveal ? .folder : .fileText) : .folderQuestion).labelStyle(.titleAndIcon) }
                                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(file.exists == false)
                                    .accessibilityLabel("\(file.buttonTitle): \(row.title)")
                            }
                        }
                    }
                }
            }
        }
        ReloadNote(ReloadStatus.shared).padding(.horizontal, Tokens.Space.s4)
    }

    /// The default first, then the profiles of the file; an undeclared one the file names is on the list too (`EngineIdentity.choices`).
    private func identityChoice(_ title: String) -> some View {
        let identity = github.identity
        return ChoicePopUp(
            label: title,
            options: EngineIdentity.options(identity),
            selection: Binding(get: { identity?.current }, set: { if $0 != identity?.current { github.choose($0) } })
        )
        .disabled(identity == nil)
        .onAppear { github.load() }
        .onChange(of: start.configExists) { github.load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in github.load() }
    }
}
