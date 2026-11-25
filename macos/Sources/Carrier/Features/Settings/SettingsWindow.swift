import AppKit
import CarrierCore
import SwiftUI

// Settings in a window of its own (not a sheet over the main one): a sidebar with the pages on the left, the chosen one on the right under a
// toolbar that says which it is, with ‹ › to go back and forward through the pages visited. The main window stays usable beside it.

/// Which page Settings is on and the pages it has been on; the page is remembered for the next time the window opens.
@MainActor @Observable final class SettingsNavigator {
    private(set) var history: SettingsHistory
    /// The place the search took the person to: its page scrolls to it and shows it for a moment, and then lets it go.
    var target: SettingsEntry?

    var page: SettingsPage { history.page }
    /// The page and, inside it, which screen (the Providers page has one for a provider and one for an account of it).
    var place: SettingsPlace { history.current }

    init() {
        history = SettingsHistory(AppPreferences().lastSettingsPage)
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

    private func remember() { AppPreferences().lastSettingsPage = page }
}

/// The one Settings window: made the first time it is asked for and kept, so it comes back where it was (its place, its size, its page).
@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private(set) var window: NSWindow?
    private let navigator = SettingsNavigator()

    var isShown: Bool { window?.isVisible == true }

    /// `page` nil keeps the one it was left on; `place` is a screen of a page; `parent` is the main window, which a first Settings window centers over.
    func show(_ page: SettingsPage?, place: SettingsPlace? = nil, model: PanelModel, over parent: NSWindow? = nil) {
        if let place { navigator.go(place) } else if let page { navigator.go(page) }
        let window = window ?? makeWindow(model: model, over: parent)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    private func makeWindow(model: PanelModel, over parent: NSWindow?) -> NSWindow {
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
        // where it was and how big; the first time, the size of a page that does not need a scroll to be read.
        // The name is accepted even when nothing was saved under it, so a frame too small to be a Settings window (the first time, the host
        // gives it none) or on no screen any more is not used, as the main window's
        _ = window.setFrameAutosaveName("CarrierSettingsWindow")
        let kept = window.contentRect(forFrameRect: window.frame).size
        let usable = kept.width >= window.contentMinSize.width && kept.height >= window.contentMinSize.height
            && NSScreen.screens.contains { $0.visibleFrame.intersects(window.frame) }
        if usable == false {
            window.setContentSize(NSSize(width: 940, height: 660))
            // over the main window, so on the screen the person is using; centered on the main screen when that one is not there to look at
            if let parent, parent.isVisible { window.setFrameOrigin(NSPoint(x: parent.frame.midX - window.frame.width / 2, y: parent.frame.midY - window.frame.height / 2)) } else { window.center() }
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
    @State private var headerAction = SettingsHeaderAction()
    @State private var headerButtons = SettingsHeaderButtons()
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
                state: model.state, canReload: model.epics.canReload, sessions: model.sessions.rows, navigator: navigator, target: $navigator.target, headerNote: $headerNote, title: $title
            )
                .navigationTitle(title?.text ?? navigator.page.title)
                .navigationSubtitle(title?.subtitle ?? navigator.page.detail)
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button(action: navigator.back) { Label("Back", systemImage: "chevron.backward") }
                            .disabled(navigator.history.canGoBack == false).keyboardShortcut("[", modifiers: .command).help("Back")
                        Button(action: navigator.forward) { Label("Forward", systemImage: "chevron.forward") }
                            .disabled(navigator.history.canGoForward == false).keyboardShortcut("]", modifiers: .command).help("Forward")
                    }
                    if let headerNote { ToolbarItem(placement: .primaryAction) { SettingsNoteView(note: headerNote, pending: ReloadStatus.shared.pending, ask: { ReloadStatus.shared.ask() }) } }
                    if let actionTitle = headerAction.title {
                        ToolbarItem(placement: .primaryAction) {
                            ToolbarPillButton(
                                title: actionTitle,
                                icon: headerAction.icon,
                                iconTint: headerAction.active ? Color.themeAccent : nil
                            ) { headerAction.run?() }
                            .glassEffect(.regular, in: .capsule)
                            .help(headerAction.help.isEmpty ? actionTitle : headerAction.help)
                            .accessibilityAddTraits(headerAction.active ? .isSelected : [])
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                    // the actions of a screen that has several (Watching): one glass capsule with a pill for each
                    if headerButtons.buttons.isEmpty == false {
                        ToolbarItem(placement: .primaryAction) {
                            HStack(spacing: 0) {
                                ForEach(headerButtons.buttons, id: \.title) { button in
                                    ToolbarPillButton(title: button.title, icon: button.icon, spinning: button.spinning) { headerButtons.run(button.title) }
                                        .disabled(button.enabled == false).help(button.help.isEmpty ? button.title : button.help)
                                }
                            }
                            .glassEffect(.regular, in: .capsule)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
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
        .environment(\.settingsHeaderAction, headerAction)
        .environment(\.settingsHeaderButtons, headerButtons)
        // the session rows of the Sidebar page's preview read what the main window gives its own
        .environment(model.actions)
        .alert("Reset \(navigator.page.title)?", isPresented: $confirmingReset) {
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
            if let note, note.tone == .problem, note.announces { AccessibilityNotification.Announcement(note.text).post() }
        }
    }
}
