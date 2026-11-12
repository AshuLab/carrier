import AppKit
import CarrierCore
import SwiftUI

/// Settings as a sheet over the main window, in the shape of the workspace chooser: a rail with the sections on the left, the chosen one on the
/// right, closed by the corner button or Esc. The readiness banner shows over every section while something is missing or being looked for.
struct SettingsSheet: View {
    let state: ConnectionState?
    @ObservedObject var setup: SetupController = .shared
    @ObservedObject private var start = StartController.shared
    @Binding var tab: SettingsPage
    @AppStorage(startOnOpenKey) private var startOnOpen = false
    @State private var headerNote: SettingsHeaderNote?
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
            case .keybindings: KeybindingsTabView()
            case .updates: UpdatesTabView()
            case .providers: ProvidersTabView(openAgents: { tab = .agents })
            case .engine: engine(banner, notConfigured: notConfigured)
            case .behavior: BehaviorTabView()
            case .repos: ReposTabView(state: state, openAgents: { tab = .agents })
            case .agents: AgentsTabView()
            case .sessions: SessionsTabView()
            case .notifications: NotificationsTabView()
            case .health: HealthTabView(state: state)
            }
        }
    }

    @ViewBuilder private func engine(_ banner: ReadinessBanner, notConfigured: String?) -> some View {
        if let notConfigured {
            Label(notConfigured, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
        }
        if banner.state == .ready {
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    StatusDot(found: notConfigured == nil)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(notConfigured == nil ? "Carrier is ready to start" : "Carrier cannot start yet").fontWeight(.semibold)
                        Text(setup.carrier ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                Button("Detect again") { setup.detect(); start.refreshConfig() }.buttonStyle(SecondaryCapsuleButtonStyle())
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .settingsCard()
            SettingsTabRow(title: "Start Carrier when the app opens", detail: notConfigured == nil ? "Carrier starts working on ready epics as soon as the app opens" : "Does nothing until the engine is configured", first: true) {
                Toggle("Start Carrier when the app opens", isOn: $startOnOpen).labelsHidden().toggleStyle(.switch).disabled(notConfigured != nil)
            }
            .padding(.horizontal, 14)
            .settingsCard()
        }
        Text("Advanced").font(.headline).padding(.top, 6).accessibilityAddTraits(.isHeader)
        UseThisCarrierField(setup: setup)
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
            Button("Detect again", action: detectAgain).disabled(detecting)
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

/// The advanced setting: a `carrier` to run instead of the Homebrew one, a path as typed (a `.ts` or `.js` one runs under `node`).
struct UseThisCarrierField: View {
    @ObservedObject var setup: SetupController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Use this carrier").fontWeight(.medium)
            HStack {
                TextField("Use this carrier", text: $setup.carrierOverride, prompt: Text("/opt/homebrew/bin/carrier"))
                    .textFieldStyle(.roundedBorder).font(.system(.caption, design: .monospaced))
                Button("Choose…") { choose() }
            }
            Text("Leave it empty to use the Homebrew one. A path ending in .ts or .js runs with node.").font(.caption).foregroundStyle(.secondary)
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
