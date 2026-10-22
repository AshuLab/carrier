import AppKit
import CarrierCore
import ServiceManagement
import SwiftUI

// The Notifications and General tabs of the Settings screen.

/// A row of these tabs: a title and a line under it on the left, the control on the right.
private struct SettingsTabRow<Control: View>: View {
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

private struct SettingsTabCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
    }
}

struct NotificationsTabView: View {
    @AppStorage(notifyNeedsYouKey) private var needsYou = true
    @AppStorage(notifyReadyForTestKey) private var readyForTest = true
    @State private var permission: NotificationPermission?

    var body: some View {
        SettingsTabCard {
            SettingsTabRow(title: "System permission", detail: permission?.text ?? "Checking…", first: true) {
                HStack {
                    if permission == .denied {
                        Button("Open System Settings") { NSWorkspace.shared.open(Self.systemSettingsURL) }
                    }
                    Button("Send a test") { SystemNotificationCentre.shared.sendTest() }.disabled(permission == .noBundle)
                }
            }
            SettingsTabRow(title: "Needs you", detail: "An epic stopped and waits for a person") {
                Toggle("Needs you", isOn: $needsYou).labelsHidden().toggleStyle(.switch)
            }
            SettingsTabRow(title: "Ready for test", detail: "An epic finished and has a PR to try") {
                Toggle("Ready for test", isOn: $readyForTest).labelsHidden().toggleStyle(.switch)
            }
        }
        .task { refresh() }
        // back from System Settings, where the person may have changed the answer
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!

    private func refresh() {
        readPermission(bundleIdentifier: Bundle.main.bundleIdentifier, reader: SystemNotificationCentre.shared) { permission = $0 }
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
        setup.settings.root.isEmpty ? nil : setup.settings.root + "/orchestrator/logs/app-start.log"
    }
}
