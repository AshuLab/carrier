import AppKit
import CarrierCore
import SwiftUI

/// Settings as a sheet over the main window, in the shape of the workspace chooser: a rail with the sections on the left, the chosen one on the
/// right and Done in the foot. The readiness banner shows over every section while something is missing or being looked for.
struct SettingsSheet: View {
    let state: ConnectionState?
    @ObservedObject var setup: SetupController = .shared
    @ObservedObject private var start = StartController.shared
    @Binding var tab: SettingsTab
    @AppStorage(startOnOpenKey) private var startOnOpen = false
    @Environment(\.dismiss) private var dismiss

    private static let rows: [(tab: SettingsTab, icon: String, detail: String)] = [
        (.engine, "cpu", "How the app starts Carrier"),
        (.behavior, "slider.horizontal.3", "How epics run"),
        (.repos, "tray.full", "What Carrier watches"),
        (.sessions, "clock.arrow.circlepath", "When sessions age out"),
        (.notifications, "bell", "What to tell you"),
        (.health, "stethoscope", "Is this Mac ready?"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                rail
                Divider()
                page.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            Divider()
            HStack {
                Spacer(minLength: 0)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .windowSheetSize()
        // what the person fixed here is what the chat host needs: look again when they are done
        .onDisappear { ChatHostStarter.shared.checkAtOpen() }
    }

    /// The sheet's name, then a row for each section.
    private var rail: some View {
        VStack(alignment: .leading, spacing: 4) {
            RailHeader(title: "Settings", detail: "How Carrier runs here", icon: "gearshape.fill")
            ForEach(Self.rows, id: \.tab) { row in
                RailRow(title: row.tab.rawValue, detail: row.detail, icon: row.icon, selected: tab == row.tab) { tab = row.tab }
            }
            Spacer(minLength: 0)
        }
        // the header sits 24 from the top and 24 from the left (16 + the row's 8), as a page's header does on the right
        .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 14).frame(width: 250)
        .background(Color.secondary.opacity(0.06))
    }

    /// The chosen section under its title, in a scroll of its own.
    private var page: some View {
        let row = Self.rows.first { $0.tab == tab } ?? Self.rows[0]
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: row.icon)
                        .font(.system(size: 16, weight: .medium)).foregroundStyle(Color.accentColor)
                        .frame(width: 36, height: 36)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.16)))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tab.rawValue).font(.title3.weight(.semibold))
                        Text(row.detail).font(.callout).foregroundStyle(.secondary)
                    }
                }
                section
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
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
            case .engine: engine(banner, notConfigured: notConfigured)
            case .behavior: BehaviorTabView()
            case .repos: ReposTabView(state: state)
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
        Text("Advanced").font(.headline).padding(.top, 6).accessibilityAddTraits(.isHeader)
        UseThisCarrierField(setup: setup)
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
