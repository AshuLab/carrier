import AppKit
import CarrierCore
import ServiceManagement
import SwiftUI

// The Notifications and General tabs of the Settings screen.

/// A row of these tabs: a title and a line under it on the left, the control on the right.
struct SettingsTabRow<Control: View>: View {
    let title: String
    let detail: String
    var first = false
    var mono = false
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                Text(detail).font(mono ? .system(size: 11.5, design: .monospaced) : .caption).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 10).frame(minHeight: 46)
        .overlay(alignment: .top) { Divider().opacity(first ? 0 : 1) }
    }
}

struct SettingsTabCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
    }
}

/// A group of a tab: a small uppercase title over a card of rows.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption2).fontWeight(.semibold).foregroundStyle(.tertiary).padding(.leading, 14).padding(.top, 8)
            SettingsTabCard { content }
        }
    }
}

struct NotificationsTabView: View {
    @AppStorage(notifyNeedsYouKey) private var needsYou = true
    @AppStorage(notifyReadyForTestKey) private var readyForTest = true
    @AppStorage(notifyProblemKey) private var problem = false
    @AppStorage(notifyOnlyWhenAwayKey) private var onlyWhenAway = true
    @State private var permission: NotificationPermission?
    @State private var testAdvice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsGroup(title: "What to tell me") {
                SettingsTabRow(title: "Needs you", detail: "An epic stopped and waits for a person", first: true) {
                    Toggle("Needs you", isOn: $needsYou).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Ready for test", detail: "An epic finished and has a PR to try") {
                    Toggle("Ready for test", isOn: $readyForTest).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "A problem", detail: "GitHub refuses a repo, or Carrier stops by itself") {
                    Toggle("A problem", isOn: $problem).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "How") {
                SettingsTabRow(title: "Only when Carrier is not in front", detail: "No banner while its window is the one you are looking at", first: true) {
                    Toggle("Only when Carrier is not in front", isOn: $onlyWhenAway).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(title: "Permission") {
                SettingsTabRow(title: "System permission", detail: permission?.text ?? "Checking…", first: true) {
                    HStack {
                        if permission != .noBundle {
                            Button("Open System Settings") { NSWorkspace.shared.open(Self.systemSettingsURL) }
                        }
                        if permission == .notAsked {
                            Button("Allow") { send() }.buttonStyle(PrimaryCapsuleButtonStyle())
                        }
                        Button("Send a test") { send() }.disabled(permission == .noBundle)
                    }
                }
            }
            if let testAdvice {
                Label(testAdvice, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange).padding(.horizontal, 14)
            }
            Text("Sound and the style of the banner are set per app in System Settings › Notifications › Carrier.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14)
        }
        .buttonStyle(.glass).buttonBorderShape(.capsule)
        .task { refresh() }
        // back from System Settings, where the person may have changed the answer
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    /// A test that macOS would swallow says why instead; otherwise it is sent (the first one also asks for the permission).
    private func send() {
        testAdvice = permission?.testAdvice
        guard testAdvice == nil else { return }
        SystemNotificationCentre.shared.sendTest()
    }

    private func refresh() {
        readPermission(bundleIdentifier: Bundle.main.bundleIdentifier, reader: SystemNotificationCentre.shared) {
            permission = $0
            if $0.testAdvice == nil { testAdvice = nil }
        }
    }
}

/// `SMAppService.mainApp`; the only place that touches the real login item.
struct MainAppLoginItem: LoginItem {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        default: .notRegistered
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

struct GeneralTabView: View {
    @ObservedObject var setup: SetupController
    @AppStorage(confirmStopKey) private var confirmStop = true
    @State private var login = OpenAtLogin(item: MainAppLoginItem(), bundled: Bundle.main.bundleIdentifier != nil)
    @State private var confirmingReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsTabCard {
                SettingsTabRow(title: "Open at login", detail: login.note ?? "Starts the app, never Carrier itself", first: true) {
                    HStack {
                        if login.needsApproval {
                            Button("Open Login Items") { login.openSystemSettings() }
                        }
                        Toggle("Open at login", isOn: Binding(get: { login.isOn }, set: { login.set($0) }))
                            .labelsHidden().toggleStyle(.switch).disabled(login.enabled == false)
                    }
                }
                SettingsTabRow(title: "Ask before stopping Carrier", detail: "Only when epics are running, since it interrupts them") {
                    Toggle("Ask before stopping Carrier", isOn: $confirmStop).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(title: "Quitting the app", detail: "Carrier keeps running. Stop it from the menu or the window.") { EmptyView() }
            }
            Text("Advanced").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary).padding(.top, 6).padding(.leading, 4)
            SettingsTabCard {
                SettingsTabRow(title: "Start log", detail: startLog.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Needs the shared root", first: true, mono: true) {
                    Button("Open") { if let startLog { NSWorkspace.shared.open(URL(fileURLWithPath: startLog)) } }
                        .disabled(startLog.map { FileManager.default.fileExists(atPath: $0) } != true)
                }
                SettingsTabRow(title: "Reset settings", detail: "Forget the saved paths and detect them again") {
                    Button("Reset…", role: .destructive) { confirmingReset = true }
                }
            }
        }
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
        .confirmationDialog("Reset settings?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive) { setup.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The saved paths are forgotten and the app asks your shell for them again.")
        }
    }

    private var startLog: String? {
        setup.settings.configPath.isEmpty ? nil : configRoot(configPath: setup.settings.configPath, home: NSHomeDirectory()) + "/orchestrator/logs/app-start.log"
    }
}
