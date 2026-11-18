import AppKit
import CarrierCore
import SwiftUI

// Settings in a window of its own (not a sheet over the main one): a sidebar with the pages on the left, the chosen one on the right under a
// toolbar that says which it is, with ‹ › to go back and forward through the pages visited. The main window stays usable beside it.

/// Which page Settings is on and the pages it has been on; the page is remembered for the next time the window opens.
@MainActor @Observable final class SettingsNavigator {
    static let lastPageKey = "settingsLastPage"
    private(set) var history: SettingsHistory

    var page: SettingsPage { history.current }

    init() {
        history = SettingsHistory(UserDefaults.standard.string(forKey: Self.lastPageKey).flatMap(SettingsPage.init(rawValue:)) ?? .general)
    }

    func go(_ page: SettingsPage) {
        history.visit(page)
        remember()
    }

    func back() {
        history.back()
        remember()
    }

    func forward() {
        history.forward()
        remember()
    }

    private func remember() { UserDefaults.standard.set(page.rawValue, forKey: Self.lastPageKey) }
}

/// The one Settings window: made the first time it is asked for and kept, so it comes back where it was (its place, its size, its page).
@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private(set) var window: NSWindow?
    private let navigator = SettingsNavigator()

    var isShown: Bool { window?.isVisible == true }

    /// `page` nil keeps the one it was left on.
    func show(_ page: SettingsPage?, model: PanelModel) {
        if let page { navigator.go(page) }
        let window = window ?? makeWindow(model: model)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    private func makeWindow(model: PanelModel) -> NSWindow {
        let host = NSHostingController(rootView: SettingsRoot(model: model, navigator: navigator).themed())
        // the split view's title and toolbar go to the window, and its content does not size it (as the main window's)
        host.sceneBridgingOptions = .all
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 760, height: 480)
        window.delegate = self
        // where it was and how big; the first time, the size of a page that does not need a scroll to be read
        if window.setFrameAutosaveName("CarrierSettingsWindow") == false {
            window.setContentSize(NSSize(width: 940, height: 660))
            window.center()
        }
        return window
    }

    /// What the person fixed here is what the chat host needs: look again when they are done.
    func windowWillClose(_ notification: Notification) { ChatHostStarter.shared.checkAtOpen() }
}

/// The window's content: the sidebar and, in the detail, the chosen page under the toolbar.
struct SettingsRoot: View {
    let model: PanelModel
    let navigator: SettingsNavigator
    @State private var headerNote: SettingsHeaderNote?

    var body: some View {
        NavigationSplitView {
            SettingsSidebar(navigator: navigator)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            SettingsPages(state: model.state, canReload: model.epics.canReload, page: navigator.page, open: navigator.go, headerNote: $headerNote)
                .navigationTitle(navigator.page.rawValue)
                .navigationSubtitle(navigator.page.detail)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button(action: navigator.back) { Label("Back", systemImage: "chevron.backward") }
                            .disabled(navigator.history.canGoBack == false).keyboardShortcut("[", modifiers: .command).help("Back")
                        Button(action: navigator.forward) { Label("Forward", systemImage: "chevron.forward") }
                            .disabled(navigator.history.canGoForward == false).keyboardShortcut("]", modifiers: .command).help("Forward")
                    }
                    if let headerNote { ToolbarItem(placement: .primaryAction) { SettingsNoteView(note: headerNote) } }
                }
        }
        // the size of a Text with no font of its own, so it follows the text size too
        .font(.scaled(13))
        // a problem appears while the person looks elsewhere: say it to VoiceOver too
        .onChange(of: headerNote) { _, note in
            if let note, note.tone == .saved || (note.tone == .problem && note.announces) { AccessibilityNotification.Announcement(note.text).post() }
        }
    }
}

/// The pages in groups, as the sidebar of System Settings lists its own: a colored tile with the page's symbol before its name.
struct SettingsSidebar: View {
    let navigator: SettingsNavigator

    var body: some View {
        List(selection: Binding(get: { navigator.page }, set: { if let page = $0 { navigator.go(page) } })) {
            ForEach(SettingsPage.Group.allCases, id: \.self) { group in
                if let heading = group.heading {
                    Section(heading) { rows(group) }
                } else {
                    Section { rows(group) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func rows(_ group: SettingsPage.Group) -> some View {
        ForEach(SettingsPage.pages(in: group), id: \.self) { page in
            Label { Text(page.rawValue) } icon: { SettingsTile(page: page) }.tag(page).help(page.detail)
        }
    }
}

struct SettingsTile: View {
    let page: SettingsPage

    var body: some View {
        Image(systemName: page.icon).font(.scaled(11, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(page.tint))
            .accessibilityHidden(true)
    }
}

extension SettingsPage {
    /// The color of the page's tile in the sidebar.
    var tint: Color {
        switch self {
        case .general, .engine, .keybindings: .gray
        case .providers: .purple
        case .appearance, .about: .blue
        case .notifications: .red
        case .dictation: .pink
        case .chat: .teal
        case .sessions: .indigo
        case .sidebar: .cyan
        case .terminal: Color(white: 0.25)
        case .agents: .orange
        case .repos, .health: .green
        case .behavior: .brown
        }
    }
}

/// The chosen page in a scroll of its own; its title is the window's toolbar. The readiness banner shows over every page while something is
/// missing or being looked for.
struct SettingsPages: View {
    let state: ConnectionState?
    let canReload: Bool
    let page: SettingsPage
    let open: (SettingsPage) -> Void
    @Binding var headerNote: SettingsHeaderNote?
    @ObservedObject var setup: SetupController = .shared
    @ObservedObject private var start = StartController.shared
    @AppStorage(startOnOpenKey) private var startOnOpen = false
    @AppStorage(AppPreferences.confirmStopKey) private var confirmStop = AppPreferences.defaultConfirmStop
    @StateObject private var github = EngineIdentityStore()
    /// What `carrier --version` and `node --version` printed for the programs the page shows; nil while they are being read.
    @State private var versions: ProgramVersions?

    var body: some View {
        ScrollView {
            section.padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .id(page)
        .onPreferenceChange(SettingsHeaderNoteKey.self) { headerNote = $0 }
    }

    @ViewBuilder private var section: some View {
        let banner = readinessBanner(missing: setup.missing, detecting: setup.detecting)
        let notConfigured = engineNotConfiguredNotice(configExists: start.configExists)
        VStack(alignment: .leading, spacing: 14) {
            if banner.state != .ready {
                ReadinessBannerView(banner: banner, detecting: setup.detecting) { setup.detect() }
            }
            if let message = setup.message {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.scaled(12)).foregroundStyle(.orange)
            }
            switch page {
            case .general: GeneralTabView()
            case .appearance: AppearanceTabView()
            case .terminal: TerminalTabView()
            case .sidebar: SidebarTabView()
            case .chat: ChatTabView()
            case .dictation: DictationTabView()
            case .keybindings: KeybindingsTabView()
            case .about: AboutTabView()
            case .providers: ProvidersTabView(openAgents: { open(.agents) })
            case .engine:
                // one container, so the versions are read once and not once per group
                VStack(alignment: .leading, spacing: 14) { engine(notConfigured: notConfigured) }
                    .task(id: versionsKey) {
                        versions = nil
                        versions = await ProgramVersions.read(setup)
                    }
            case .behavior: BehaviorTabView()
            case .repos: ReposTabView(state: state, canReload: canReload, openAgents: { open(.agents) })
            case .agents: AgentsTabView()
            case .sessions: SessionsTabView()
            case .notifications: NotificationsTabView()
            case .health: HealthTabView(state: state)
            }
        }
    }

    /// Changes when a program the page shows does, and when a detection ends (an upgrade keeps the path), so the versions are read again.
    private var versionsKey: String { "\(setup.carrier ?? "")|\(setup.settings.node)|\(setup.settings.path)|\(setup.detecting)" }

    @ViewBuilder private func engine(notConfigured: String?) -> some View {
        if let notConfigured {
            Label(notConfigured, systemImage: "exclamationmark.triangle.fill").font(.scaled(12)).foregroundStyle(.orange)
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
            SettingsGroup(title: group.title) {
                ForEach(Array(group.rows.enumerated()), id: \.element.title) { index, row in
                    SettingsTabRow(title: row.title, detail: row.detail, first: index == 0, note: row.note ?? row.file?.shown, problem: row.problem) {
                        switch row.id {
                        case .startOnOpen: Toggle(row.title, isOn: $startOnOpen).labelsHidden().toggleStyle(.switch).disabled(notConfigured != nil)
                        case .confirmStop: Toggle(row.title, isOn: $confirmStop).labelsHidden().toggleStyle(.switch)
                        case .carrier: CarrierChoice(setup: setup, offersHomebrew: row.offersHomebrew)
                        case .node, .path: EmptyView()
                        case .lookAgain:
                            HStack(spacing: 8) {
                                // beside the button, so the button keeps its size and its name while it works
                                if setup.detecting { ProgressView().controlSize(.small).accessibilityLabel("Detecting") }
                                Button { setup.detect(); start.refreshConfig() } label: { Label("Detect", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon) }
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
                                } label: { Label(file.buttonTitle, systemImage: file.exists ? (file.action == .reveal ? "folder" : "doc.text") : "questionmark.folder").labelStyle(.titleAndIcon) }
                                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(file.exists == false)
                                    .accessibilityLabel("\(file.buttonTitle): \(row.title)")
                            }
                        }
                    }
                }
            }
        }
        ReloadNote().padding(.horizontal, 4)
    }

    /// The default first, then the profiles of the file; an undeclared one the file names is on the list too (`EngineIdentity.choices`).
    private func identityChoice(_ title: String) -> some View {
        let identity = github.identity
        return ChoicePopUp(
            label: title,
            options: EngineIdentity.options(identity),
            selection: Binding(get: { identity?.current }, set: { if $0 != identity?.current { github.choose($0) } }),
            width: 180
        )
        .disabled(identity == nil)
        .onAppear { github.load() }
        .onChange(of: start.configExists) { github.load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in github.load() }
    }
}

struct ReadinessBannerView: View {
    let banner: ReadinessBanner
    let detecting: Bool
    let detectAgain: () -> Void

    var body: some View {
        let tint: Color = banner.state == .ready ? .green : .orange
        HStack(spacing: 12) {
            if banner.state == .detecting {
                ProgressView().controlSize(.small)
            } else {
                StatusDot(found: banner.state == .ready)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(banner.title).fontWeight(.semibold)
                Text(banner.detail).font(.scaled(11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: detectAgain) { Label("Detect", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon) }
                .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(detecting)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(tint.opacity(0.13)))
        .accessibilityElement(children: .combine)
    }
}

/// The round check or exclamation mark in front of a banner or a row.
struct StatusDot: View {
    let found: Bool

    var body: some View {
        Image(systemName: found ? "checkmark" : "exclamationmark")
            .font(.scaled(10, weight: .heavy)).foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(found ? Color.green : Color.orange))
            .accessibilityLabel(found ? "Found" : "Not found")
    }
}

/// The buttons of the `carrier` row: choose another one (a path as chosen; a `.ts` or `.js` one runs under `node`), and go back to the Homebrew one.
struct CarrierChoice: View {
    @ObservedObject var setup: SetupController
    let offersHomebrew: Bool

    var body: some View {
        HStack(spacing: 8) {
            if offersHomebrew {
                Button { setup.carrierOverride = "" } label: { Label("Use the Homebrew one", systemImage: "arrow.uturn.backward").labelStyle(.titleAndIcon) }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
            Button { choose() } label: { Label("Use another…", systemImage: "folder.badge.plus").labelStyle(.titleAndIcon) }
                .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { setup.carrierOverride = url.path }
    }
}
