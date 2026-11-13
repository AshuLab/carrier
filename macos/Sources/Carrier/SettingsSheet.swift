import AppKit
import CarrierCore
import SwiftUI

/// Settings as a sheet over the main window, in the shape of the workspace chooser: a rail with the sections on the left, the chosen one on the
/// right, closed by the corner button or Esc. The readiness banner shows over every section while something is missing or being looked for.
struct SettingsSheet: View {
    let state: ConnectionState?
    let canReload: Bool
    @ObservedObject var setup: SetupController = .shared
    @ObservedObject private var start = StartController.shared
    @Binding var tab: SettingsPage
    @AppStorage(startOnOpenKey) private var startOnOpen = false
    @AppStorage(AppPreferences.confirmStopKey) private var confirmStop = AppPreferences.defaultConfirmStop
    @StateObject private var github = EngineIdentityStore()
    @State private var headerNote: SettingsHeaderNote?
    /// What `carrier --version` and `node --version` printed for the programs the page shows; nil while they are being read.
    @State private var versions: ProgramVersions?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SettingsRail(page: $tab)
                Divider()
                page.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .windowSheetSize()
        // what the person fixed here is what the chat host needs: look again when they are done
        .onDisappear { ChatHostStarter.shared.checkAtOpen() }
    }

    /// The chosen page in a scroll of its own, under its title, which stays at the top while the page scrolls beneath it (the scroll edge
    /// effect the main window's bars have).
    private var page: some View {
        ScrollView {
            section.padding(.horizontal, 24).padding(.bottom, 24).padding(.top, 8).frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onPreferenceChange(SettingsHeaderNoteKey.self) { headerNote = $0 }
        .safeAreaBar(edge: .top, spacing: 0) {
            SettingsPageHeader(page: tab, note: headerNote).padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                // closing is a corner button (Esc closes a sheet as well), not a footer
                .overlay(alignment: .topTrailing) { IconButton(icon: "xmark", name: "Close", shortcut: "Esc") { dismiss() }.padding(.top, 24).padding(.trailing, 16) }
        }
    }

    @ViewBuilder private var section: some View {
        let banner = readinessBanner(missing: setup.missing, detecting: setup.detecting)
        let notConfigured = engineNotConfiguredNotice(configExists: start.configExists)
        VStack(alignment: .leading, spacing: 14) {
            if banner.state != .ready {
                ReadinessBannerView(banner: banner, detecting: setup.detecting) { setup.detect() }
            }
            if let message = setup.message {
                Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
            }
            switch tab {
            case .general: GeneralTabView()
            case .appearance: AppearanceTabView()
            case .sidebar: SidebarTabView()
            case .chat: ChatTabView()
            case .dictation: DictationTabView()
            case .keybindings: KeybindingsTabView()
            case .updates: UpdatesTabView()
            case .providers: ProvidersTabView(openAgents: { tab = .agents })
            case .engine:
                // one container, so the versions are read once and not once per group
                VStack(alignment: .leading, spacing: 14) { engine(notConfigured: notConfigured) }
                    .task(id: versionsKey) {
                        versions = nil
                        versions = await ProgramVersions.read(setup)
                    }
            case .behavior: BehaviorTabView()
            case .repos: ReposTabView(state: state, canReload: canReload, openAgents: { tab = .agents })
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
            Label(notConfigured, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
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

/// The rail: the pages of each group in order, the heading of a group over its pages when it has one.
struct SettingsRail: View {
    @Binding var page: SettingsPage

    /// What the rail draws: each group with its pages.
    static let sections = SettingsPage.Group.allCases.map { (group: $0, pages: SettingsPage.pages(in: $0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RailHeader(title: "Settings", detail: "How Carrier runs here")
            // the pages scroll under the header, so the last ones stay in reach in a short window
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Self.sections, id: \.group) { section in
                        if let heading = section.group.heading {
                            Text(heading).sectionLabel()
                                .padding(.leading, 8).padding(.top, 10).accessibilityAddTraits(.isHeader)
                        }
                        ForEach(section.pages, id: \.self) { row in
                            RailRow(title: row.rawValue, detail: row.detail, icon: row.icon, selected: page == row) { page = row }
                        }
                    }
                }
            }
        }
        // the header sits 24 from the top and 24 from the left (16 + the row's 8), as a page's header does on the right
        .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 14).frame(width: 250)
        .background(Color.secondary.opacity(0.06))
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
                Text(banner.detail).font(.caption).foregroundStyle(.secondary)
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
