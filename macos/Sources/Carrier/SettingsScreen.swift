import AppKit
import CarrierCore
import SwiftUI

/// Settings as a screen of the main window: the readiness banner (only while something is missing or being looked for), five tabs.
struct SettingsScreen: View {
    let state: ConnectionState?
    @ObservedObject var setup: SetupController = .shared
    @ObservedObject private var start = StartController.shared
    @Binding var tab: SettingsTab
    @AppStorage(startOnOpenKey) private var startOnOpen = false

    var body: some View {
        let model = readinessBanner(missing: setup.missing, detecting: setup.detecting)
        let notConfigured = engineNotConfiguredNotice(configExists: start.configExists)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if model.state != .ready {
                    ReadinessBannerView(banner: model, detecting: setup.detecting) { setup.detect() }
                }
                if let message = setup.message {
                    Label(message, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                }
                UnderlineTabs(items: SettingsTab.allCases.map { UnderlineTabs.Item(id: $0, title: $0.rawValue) }, selection: $tab)
                if tab == .engine {
                    if let notConfigured {
                        Label(notConfigured, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                    }
                    if model.state == .ready {
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
                            Button("Detect again") { setup.detect(); start.refreshConfig() }.buttonStyle(.glass).buttonBorderShape(.capsule)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
                        SettingsTabRow(title: "Start Carrier when the app opens", detail: notConfigured == nil ? "Carrier starts working on ready epics as soon as the app opens" : "Does nothing until the engine is configured", first: true) {
                            Toggle("Start Carrier when the app opens", isOn: $startOnOpen).labelsHidden().toggleStyle(.switch).disabled(notConfigured != nil)
                        }
                        .padding(.horizontal, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.secondary.opacity(0.07)))
                    }
                    Text("Advanced").font(.headline).padding(.top, 6)
                    UseThisCarrierField(setup: setup)
                } else if tab == .behavior {
                    BehaviorTabView(state: state)
                } else if tab == .repos {
                    ReposTabView(state: state)
                } else if tab == .notifications {
                    NotificationsTabView()
                } else {
                    HealthTabView(state: state)
                }
            }
            .padding(18)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        // what the person fixed here is what the chat host needs: look again when they leave, as the Settings window does when it closes
        .onDisappear { ChatHostStarter.shared.checkAtOpen() }
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
            .font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
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
                TextField("/opt/homebrew/bin/carrier", text: $setup.carrierOverride)
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
