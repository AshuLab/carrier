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

struct UpdatesTabView: View {
    @State private var prefs = UpdatePrefs(updater: AppUpdater.updater)
    private var engine: EngineUpdateState { ChatHostStarter.shared.engineUpdate }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        SettingsPageBody {
            SettingsGroup(title: "This Carrier") {
                SettingsTabRow(
                    title: "Version \(version)",
                    detail: prefs.updater == nil ? "This build does not look for updates" : "Last checked: \(updateCheckedText(prefs.last, now: Date()))",
                    first: true
                ) {
                    Button { prefs.checkNow() } label: { Label("Check now", systemImage: "arrow.clockwise") }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).disabled(prefs.canCheck == false)
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
            SettingsGroup(title: "Updates") {
                SettingsTabRow(title: "Check by itself", detail: "Looks for a newer Carrier when it opens and from time to time", first: true) {
                    Toggle("Check by itself", isOn: Binding(get: { prefs.checks }, set: prefs.setChecks))
                        .labelsHidden().toggleStyle(.switch).disabled(prefs.updater == nil)
                }
                SettingsTabRow(title: "Install by itself", detail: "Installs when you quit; off, it asks before it installs") {
                    Toggle("Install by itself", isOn: Binding(get: { prefs.installs }, set: prefs.setInstalls))
                        .labelsHidden().toggleStyle(.switch).disabled(prefs.updater == nil || prefs.checks == false)
                }
            }
        }
    }
}
