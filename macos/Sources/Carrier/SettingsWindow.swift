import AppKit
import CarrierCore
import SwiftUI

// Settings in a window of its own (not a sheet over the main one): a sidebar with the pages on the left, the chosen one on the right under a
// toolbar that says which it is, with ‹ › to go back and forward through the pages visited. The main window stays usable beside it.

/// Which page Settings is on and the pages it has been on; the page is remembered for the next time the window opens.
@MainActor @Observable final class SettingsNavigator {
    static let lastPageKey = "settingsLastPage"
    private(set) var history: SettingsHistory
    /// The place the search took the person to: its page scrolls to it and shows it for a moment, and then lets it go.
    var target: SettingsEntry?

    var page: SettingsPage { history.page }
    /// The page and, inside it, which screen (the Providers page has one for a provider and one for an account of it).
    var place: SettingsPlace { history.current }

    init() {
        history = SettingsHistory(UserDefaults.standard.string(forKey: Self.lastPageKey).flatMap(SettingsPage.init(rawValue:)) ?? .general)
    }

    func go(_ page: SettingsPage) { go(SettingsPlace(page)) }

    func go(_ place: SettingsPlace) {
        history.visit(place)
        remember()
    }

    /// Goes to a place the search found: its page, and the row or group on it, or the screen of a provider or an account (each screen on the way
    /// is a place, so back leaves one at a time).
    func open(_ entry: SettingsEntry) {
        go(entry.page)
        for length in entry.path.indices { go(SettingsPlace(entry.page, path: Array(entry.path.prefix(length + 1)))) }
        // a provider or an account has no row of its own on the page to show; a row of a screen is scrolled to once that screen is open
        target = entry.isPage ? nil : entry
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

    /// `page` nil keeps the one it was left on; `place` is a screen of a page.
    func show(_ page: SettingsPage?, place: SettingsPlace? = nil, model: PanelModel) {
        if let place { navigator.go(place) } else if let page { navigator.go(page) }
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
    @State private var query = ""
    @State private var resetter = SettingsReset()
    @State private var saver = SettingsSave()
    @State private var title: SettingsTitle?
    @State private var confirmingReset = false

    var body: some View {
        @Bindable var navigator = navigator
        NavigationSplitView {
            SettingsSidebar(navigator: navigator, query: $query)
                .searchable(text: $query, placement: .sidebar, prompt: "Search settings")
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            SettingsPages(
                state: model.state, canReload: model.epics.canReload, navigator: navigator, target: $navigator.target, headerNote: $headerNote, title: $title
            )
                .navigationTitle(title?.text ?? navigator.page.rawValue)
                .navigationSubtitle(title?.subtitle ?? navigator.page.detail)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button(action: navigator.back) { Label("Back", systemImage: "chevron.backward") }
                            .disabled(navigator.history.canGoBack == false).keyboardShortcut("[", modifiers: .command).help("Back")
                        Button(action: navigator.forward) { Label("Forward", systemImage: "chevron.forward") }
                            .disabled(navigator.history.canGoForward == false).keyboardShortcut("]", modifiers: .command).help("Forward")
                    }
                    if let headerNote { ToolbarItem(placement: .primaryAction) { SettingsNoteView(note: headerNote) } }
                    // the save of a screen that edits something (an account): on its own glass pill, as the window's other actions
                    if let saveTitle = saver.title {
                        ToolbarItem(placement: .primaryAction) {
                            AccentGlassPillButton(title: saveTitle, icon: saver.icon) { saver.run?() }.disabled(saver.enabled == false)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                    // only on a page that has a Reset: a menu with nothing to do is not drawn
                    if resetter.action != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                Button { confirmingReset = true } label: { Label("Reset this page…", systemImage: "arrow.counterclockwise") }
                            } label: {
                                Image(systemName: "ellipsis")
                            }
                            .menuIndicator(.hidden).help("Page actions")
                        }
                    }
                }
        }
        .environment(\.settingsReset, resetter)
        .environment(\.settingsSave, saver)
        // the session rows of the Sidebar page's preview read what the main window gives its own
        .environment(model.actions)
        .alert("Reset \(navigator.page.rawValue)?", isPresented: $confirmingReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { resetter.action?() }
        } message: {
            Text("Every setting on this page goes back to how it came. This can’t be undone.")
        }
        // the size of a Text with no font of its own, so it follows the text size too
        .font(.scaled(13))
        // the search finds the providers and accounts of this Mac, which only the host knows
        .task { await AppHealth.providers.load() }
        // a problem appears while the person looks elsewhere: say it to VoiceOver too
        .onChange(of: headerNote) { _, note in
            if let note, note.tone == .saved || (note.tone == .problem && note.announces) { AccessibilityNotification.Announcement(note.text).post() }
        }
    }
}

/// The pages in groups, as the sidebar of System Settings lists its own: a colored tile with the page's symbol before its name.
struct SettingsSidebar: View {
    let navigator: SettingsNavigator
    @Binding var query: String
    @ObservedObject private var setup = SetupController.shared

    var body: some View {
        if query.trimmingCharacters(in: .whitespaces).isEmpty { pages } else { results }
    }

    private var pages: some View {
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
        // the theme's color, as the main window's sidebar has it, and not the system's material
        .scrollContentBackground(.hidden).themedSidebarBackground()
    }

    /// The providers, accounts and servers of this Mac, which the static index cannot know: the Providers page's own answer, when it has one.
    private var providersEntries: [SettingsEntry] {
        guard case .reply(let reply) = AppHealth.providers.outcome, reply.problem == nil else { return [] }
        return providersSearchEntries(providersPage(reply, config: currentConfig(), chat: try? currentChatConfig()))
    }

    /// What the search found, under the pages it is in; choosing one opens the page and shows the row.
    @ViewBuilder private var results: some View {
        let found = settingsResults(query, in: settingsIndex + providersEntries)
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if found.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                ForEach(SettingsPage.allCases.filter { page in found.contains { $0.page == page } }, id: \.self) { page in
                    Section {
                        ForEach(found.filter { $0.page == page }) { entry in
                            Button {
                                navigator.open(entry)
                                query = ""
                            } label: {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(marked(entry.title, words: words))
                                    Text(marked(entry.isPage ? entry.detail : [entry.group, entry.detail].filter { !$0.isEmpty }.joined(separator: " · "), words: words))
                                        .font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Label { Text(page.rawValue) } icon: { SettingsTile(page: page) }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden).themedSidebarBackground()
        }
    }

    /// The words of the search shown on what matched them.
    private func marked(_ text: String, words: [String]) -> AttributedString {
        var out = AttributedString(text)
        for word in words {
            var from = out.startIndex
            while let found = out[from...].range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
                out[found].backgroundColor = Color.yellow.opacity(0.45)
                from = found.upperBound
            }
        }
        return out
    }

    private func rows(_ group: SettingsPage.Group) -> some View {
        ForEach(SettingsPage.pages(in: group), id: \.self) { page in
            Label { Text(page.rawValue) } icon: { SettingsTile(page: page) }.tag(page).help(page.detail)
                // what Carrier is missing is fixed on these two pages: the sidebar says so, and the banner is on them alone
                .badge(page == .engine || page == .health ? missing : 0)
        }
    }

    private var missing: Int { readinessBanner(missing: setup.missing, detecting: setup.detecting).state == .missing ? 1 : 0 }
}

struct SettingsTile: View {
    let page: SettingsPage
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // the system's colors are made for a light window: on a dark one they glow, so they are mixed with black there
        Glyph(page.icon, size: 13, bold: true).foregroundStyle(.white.opacity(scheme == .dark ? 0.88 : 1))
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(page.tint.mix(with: .black, by: scheme == .dark ? 0.4 : 0.05)))
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
        case .keepAwake: .yellow
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

/// How wide the pages of rows are, whatever the window: the same for every page that is a column (`SettingsPage.isColumn`).
let settingsColumnWidth: CGFloat = 760

/// The chosen page in a scroll of its own; its title is the window's toolbar. The readiness banner shows over every page while something is
/// missing or being looked for.
struct SettingsPages: View {
    let state: ConnectionState?
    let canReload: Bool
    let navigator: SettingsNavigator
    /// The place the search chose: scrolled to and shown for a moment, once the page is drawn.
    @Binding var target: SettingsEntry?
    @Binding var headerNote: SettingsHeaderNote?
    /// What a screen of a page says of itself in the toolbar (a provider's name, an account's), when it is not the page's.
    @Binding var title: SettingsTitle?
    @ObservedObject var setup: SetupController = .shared
    @ObservedObject private var start = StartController.shared
    @AppStorage(startOnOpenKey) private var startOnOpen = false
    @AppStorage(AppPreferences.confirmStopKey) private var confirmStop = AppPreferences.defaultConfirmStop
    @StateObject private var github = EngineIdentityStore()
    /// What `carrier --version` and `node --version` printed for the programs the page shows; nil while they are being read.
    @State private var versions: ProgramVersions?
    @State private var highlight: String?
    /// The width the page has, to center a column in it.
    @State private var width: CGFloat = 0
    private var page: SettingsPage { navigator.page }
    private var inset: CGFloat { page.isColumn ? max(0, (width - settingsColumnWidth) / 2) : 0 }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if page.usesForm {
                    // the form scrolls by itself; what is said over every page of its own kind stays above it
                    VStack(spacing: 0) {
                        notices.padding(.horizontal, 24 + inset).padding(.top, showsNotices ? 24 : 0).padding(.bottom, showsNotices ? 8 : 0)
                        pageContent
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            notices
                            pageContent
                        }
                        .padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
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
            VStack(alignment: .leading, spacing: 8) {
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
        case .about: AboutTabView()
        case .providers: ProvidersTabView(place: navigator.place, go: navigator.go, back: navigator.back, openAgents: { navigator.go(.agents) })
        case .engine:
            // one container, so the versions are read once and not once per group
            SettingsPageBody { engine(notConfigured: notConfigured) }
                .task(id: versionsKey) {
                    versions = nil
                    versions = await ProgramVersions.read(setup)
                }
        case .behavior: BehaviorTabView()
        case .repos: ReposTabView(state: state, canReload: canReload, openAgents: { navigator.go(.agents) })
        case .agents: AgentsTabView(place: navigator.place, go: navigator.go)
        case .sessions: SessionsTabView()
        case .notifications: NotificationsTabView()
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
        ReloadNote().padding(.horizontal, 4)
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
            Button(action: detectAgain) { Label("Detect", icon: .refresh).labelStyle(.titleAndIcon) }
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
        Glyph(found ? .check : .exclamation, size: 11, bold: true).foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(found ? Color.green : Color.orange))
            .accessibilityElement(children: .ignore).accessibilityLabel(found ? "Found" : "Not found")
    }
}

/// The buttons of the `carrier` row: choose another one (a path as chosen; a `.ts` or `.js` one runs under `node`), and go back to the Homebrew one.
struct CarrierChoice: View {
    @ObservedObject var setup: SetupController
    let offersHomebrew: Bool

    var body: some View {
        HStack(spacing: 8) {
            if offersHomebrew {
                Button { setup.carrierOverride = "" } label: { Label("Use the Homebrew one", icon: .undo).labelStyle(.titleAndIcon) }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
            Button { choose() } label: { Label("Use another…", icon: .folderPlus).labelStyle(.titleAndIcon) }
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
