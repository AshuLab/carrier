import CarrierCore
import Foundation
import Sparkle
import SwiftUI

/// The updater's two choices and its last check, read from Sparkle's own preferences (they are KVO-compliant) and written back to them.
/// Without an updater (a fixture, `swift run`) the page shows that and changes nothing.
@MainActor @Observable final class UpdatePrefs {
    private(set) var checks = false
    private(set) var installs = false
    private(set) var canCheck = false
    private(set) var last: Date?
    let updater: SPUUpdater?
    @ObservationIgnored private var watching: [NSKeyValueObservation] = []

    init(updater: SPUUpdater?) {
        self.updater = updater
        guard let updater else { return }
        refresh()
        watching = [
            updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.automaticallyDownloadsUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.canCheckForUpdates) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            updater.observe(\.lastUpdateCheckDate) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
        ]
    }

    private func refresh() {
        guard let updater else { return }
        checks = updater.automaticallyChecksForUpdates
        installs = updater.automaticallyDownloadsUpdates
        canCheck = updater.canCheckForUpdates
        last = updater.lastUpdateCheckDate
    }

    func setChecks(_ on: Bool) { updater?.automaticallyChecksForUpdates = on }
    func setInstalls(_ on: Bool) { updater?.automaticallyDownloadsUpdates = on }
    func checkNow() { updater?.checkForUpdates() }
}

/// The About page: what this Carrier is (icon, version, links), how it updates and the engine's own update.
struct AboutTabView: View {
    @State private var prefs = UpdatePrefs(updater: AppUpdater.updater)
    @AppStorage(AppPreferences.updateDelayKey) private var delay = 0
    /// The same model as the sidebar's pill: an update found keeps Sparkle's session open, so `canCheckForUpdates` is false until it is taken or dismissed.
    private let model = AppUpdater.model
    private var engine: EngineUpdateState { ChatHostStarter.shared.engineUpdate }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// The app's mark, its name and version, and the links of the About panel under them.
    private var identity: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Carrier").font(.scaled(17, weight: .semibold))
                    Text("Version \(version)").font(.scaled(12)).foregroundStyle(.secondary).textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    ForEach(aboutLinks, id: \.title) { link in
                        Button { NSWorkspace.shared.open(link.url) } label: { Label(link.title, systemImage: "arrow.up.right") }
                            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thisCarrierDetail: String {
        if let update = model.flow.phase.settingsDetail { return update }
        return prefs.updater == nil ? "This build does not look for updates" : "Last checked: \(updateCheckedText(prefs.last, now: Date()))"
    }

    @ViewBuilder private var thisCarrierAction: some View {
        if let action = model.flow.phase.settingsAction {
            HStack(spacing: 10) {
                if action.working { ProgressView().controlSize(.mini).frame(width: 16, height: 16).accessibilityLabel("Updating") }
                Button { model.press() } label: { Label(action.title, systemImage: action.symbol) }
                    .buttonStyle(PrimaryCapsuleButtonStyle()).disabled(action.working)
            }
        } else {
            Button { prefs.checkNow() } label: { Label("Check now", systemImage: "arrow.clockwise") }
                .buttonStyle(SecondaryCapsuleButtonStyle()).disabled(prefs.canCheck == false)
        }
    }

    var body: some View {
        SettingsPageBody {
            SettingsGroup(title: "About") {
                identity
                SettingsTabRow(title: "Star Carrier on GitHub", detail: "A star helps other people find it") {
                    Button { if let url = browserURL(repositoryURL) { NSWorkspace.shared.open(url) } } label: { Label("Star on GitHub", systemImage: "star") }
                        .buttonStyle(SecondaryCapsuleButtonStyle())
                }
            }
            SettingsGroup(title: "Updates") {
                SettingsTabRow(title: "Carrier \(version)", detail: thisCarrierDetail, first: true) { thisCarrierAction }
                SettingsTabRow(title: "Check by itself", detail: "Looks for a newer Carrier when it opens and from time to time") {
                    Toggle("Check by itself", isOn: Binding(get: { prefs.checks }, set: prefs.setChecks))
                        .labelsHidden().toggleStyle(.switch).disabled(prefs.updater == nil)
                }
                SettingsTabRow(title: "Install by itself", detail: "Installs when you quit; off, it asks before it installs") {
                    Toggle("Install by itself", isOn: Binding(get: { prefs.installs }, set: prefs.setInstalls))
                        .labelsHidden().toggleStyle(.switch).disabled(prefs.updater == nil || prefs.checks == false)
                }
                SettingsStackedRow(title: "Update delay", detail: "Waits this long after a release before offering it by itself, so a new version is tried by others first. Check now ignores it") {
                    SegmentedChoice(
                        options: updateDelayChoices.map { (value: $0, title: $0 == 0 ? "None" : $0 == 1 ? "1 day" : "\($0) days", icon: nil) },
                        selection: Binding(get: { clampedUpdateDelay(delay) }, set: { delay = $0 })
                    )
                    .accessibilityLabel("Update delay").disabled(prefs.updater == nil)
                }
            }
            SettingsGroup(title: "Engine") {
                SettingsTabRow(title: "Engine and chat host", detail: engine.line, first: true) {
                    HStack(spacing: 10) {
                        switch engine {
                        case .running: ProgressView().controlSize(.mini).frame(width: 16, height: 16).accessibilityLabel("Updating")
                        case .upToDate, .updated: StatusMark(symbol: "checkmark", color: .green, label: "Up to date")
                        case .failed: StatusMark(symbol: "xmark", color: .orange, label: "Failed")
                        case .unknown: EmptyView()
                        }
                        if engine.canRetry {
                            Button { ChatHostStarter.shared.retryUpgrade() } label: { Label("Try again", systemImage: "arrow.clockwise") }
                                .buttonStyle(SecondaryCapsuleButtonStyle())
                        }
                    }
                }
                if let notice = engine.notice {
                    Text(notice.line).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).copyOnHover(notice.line)
                        .padding(.vertical, 10)
                }
            }
        }
    }
}
