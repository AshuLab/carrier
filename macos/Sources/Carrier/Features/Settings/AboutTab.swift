import CarrierCore
import Foundation
import SwiftUI

/// The About page: what this Carrier is (icon, version, links), how it updates and the engine's own update.
struct AboutTabView: View {
    /// The same updater as the sidebar's pill: an update found keeps Sparkle's session open, so `canCheck` is false until it is taken or dismissed.
    let updater: any Updater
    @AppStorage(Preference.updatesDelayDays) private var delay
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
                        Button { NSWorkspace.shared.open(link.url) } label: { Label(link.title, icon: .arrowUpRight) }
                            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thisCarrierDetail: String {
        if let update = updater.flow.phase.settingsDetail { return update }
        return updater.isRunning ? "Last checked: \(updateCheckedText(updater.lastCheck, now: Date()))" : "This build does not look for updates"
    }

    @ViewBuilder private var thisCarrierAction: some View {
        if let action = updater.flow.phase.settingsAction {
            HStack(spacing: 10) {
                if action.working { ProgressView().controlSize(.mini).frame(width: 16, height: 16).accessibilityLabel("Updating") }
                Button { updater.press() } label: { Label(action.title, icon: action.symbol) }
                    .buttonStyle(PrimaryCapsuleButtonStyle()).disabled(action.working)
            }
        } else {
            Button { updater.checkNow() } label: { Label("Check now", icon: .refresh) }
                .buttonStyle(SecondaryCapsuleButtonStyle()).disabled(updater.canCheck == false)
        }
    }

    var body: some View {
        SettingsPageBody {
            SettingsGroup(id: "about", title: "About") {
                identity
                SettingsTabRow(id: "star-carrier-on-github", title: "Star Carrier on GitHub", detail: "A star helps other people find it") {
                    Button { if let url = browserURL(repositoryURL) { NSWorkspace.shared.open(url) } } label: { Label("Star on GitHub", icon: .star) }
                        .buttonStyle(SecondaryCapsuleButtonStyle())
                }
            }
            SettingsGroup(id: "updates", title: "Updates") {
                SettingsTabRow(title: "Carrier \(version)", detail: thisCarrierDetail, first: true) { thisCarrierAction }
                SettingsTabRow(id: "check-by-itself", title: "Check by itself", detail: "Looks for a newer Carrier when it opens and from time to time") {
                    Toggle("Check by itself", isOn: Binding(get: { updater.checksAutomatically }, set: { updater.checksAutomatically = $0 }))
                        .labelsHidden().toggleStyle(.switch).disabled(updater.isRunning == false)
                }
                SettingsTabRow(id: "install-by-itself", title: "Install by itself", detail: "Installs when you quit; off, it asks before it installs") {
                    Toggle("Install by itself", isOn: Binding(get: { updater.installsAutomatically }, set: { updater.installsAutomatically = $0 }))
                        .labelsHidden().toggleStyle(.switch).disabled(updater.isRunning == false || updater.checksAutomatically == false)
                }
                SettingsStackedRow(id: "update-delay", title: "Update delay", detail: "Waits this long after a release before offering it by itself, so a new version is tried by others first. Check now ignores it") {
                    SegmentedChoice(
                        options: updateDelayChoices.map { (value: $0, title: $0 == 0 ? "None" : $0 == 1 ? "1 day" : "\($0) days", icon: nil) },
                        selection: Binding(get: { clampedUpdateDelay(delay) }, set: { delay = $0 })
                    )
                    .accessibilityLabel("Update delay").disabled(updater.isRunning == false)
                }
            }
            SettingsGroup(id: "engine", title: "Engine") {
                SettingsTabRow(id: "engine-and-chat-host", title: "Engine and chat host", detail: engine.line, first: true) {
                    HStack(spacing: 10) {
                        switch engine {
                        case .running: ProgressView().controlSize(.mini).frame(width: 16, height: 16).accessibilityLabel("Updating")
                        case .upToDate, .updated: StatusMark(symbol: .check, color: .green, label: "Up to date")
                        case .failed: StatusMark(symbol: .close, color: .orange, label: "Failed")
                        case .unknown: EmptyView()
                        }
                        if engine.canRetry {
                            Button { ChatHostStarter.shared.retryUpgrade() } label: { Label("Try again", icon: .refresh) }
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
