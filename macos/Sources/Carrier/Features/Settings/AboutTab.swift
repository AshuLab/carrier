import CarrierCore
import CarrierUI
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
        HStack(alignment: .center, spacing: Tokens.Space.s16) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.s8) {
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text(Copy.appName()).scaledFont(17, weight: .semibold)
                    Text(Copy.aboutVersion(version: version)).scaledFont(12).foregroundStyle(.secondary).textSelection(.enabled)
                }
                HStack(spacing: Tokens.Space.s8) {
                    ForEach(aboutLinks(), id: \.title) { link in
                        Button { NSWorkspace.shared.open(link.url) } label: { Label(link.title, icon: .arrowUpRight) }
                            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Tokens.Space.s16).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thisCarrierDetail: String {
        if let update = updater.flow.phase.settingsDetail() { return update }
        return updater.isRunning ? Copy.aboutLastChecked(when: updateCheckedText(updater.lastCheck, now: Date())) : Copy.aboutNoUpdates()
    }

    @ViewBuilder private var thisCarrierAction: some View {
        if let action = updater.flow.phase.settingsAction() {
            HStack(spacing: Tokens.Space.s10) {
                if action.working { ProgressView().controlSize(.mini).frame(width: 16, height: 16).accessibilityLabel(Copy.updatesUpdating()) }
                Button { updater.press() } label: { Label(action.title, icon: action.symbol) }
                    .buttonStyle(PrimaryCapsuleButtonStyle()).disabled(action.working)
            }
        } else {
            Button { updater.checkNow() } label: { Label(Copy.aboutCheckNow(), icon: .refresh) }
                .buttonStyle(SecondaryCapsuleButtonStyle()).disabled(updater.canCheck == false)
        }
    }

    var body: some View {
        SettingsPageBody {
            SettingsGroup(id: "about", title: Copy.aboutGroupAbout()) {
                identity
                SettingsTabRow(id: "star-carrier-on-github", title: Copy.aboutStarTitle(), detail: Copy.aboutStarDetail()) {
                    Button { if let url = browserURL(repositoryURL) { NSWorkspace.shared.open(url) } } label: { Label(Copy.aboutStarButton(), icon: .star) }
                        .buttonStyle(SecondaryCapsuleButtonStyle())
                }
            }
            SettingsGroup(id: "updates", title: Copy.aboutGroupUpdates()) {
                SettingsTabRow(title: Copy.aboutRowCarrier(version: version), detail: thisCarrierDetail, first: true) { thisCarrierAction }
                SettingsTabRow(id: "check-by-itself", title: Copy.aboutRowCheck(), detail: Copy.aboutRowCheckDetail()) {
                    Toggle(Copy.aboutRowCheck(), isOn: Binding(get: { updater.checksAutomatically }, set: { updater.checksAutomatically = $0 }))
                        .labelsHidden().toggleStyle(.switch).disabled(updater.isRunning == false)
                }
                SettingsTabRow(id: "install-by-itself", title: Copy.aboutRowInstall(), detail: Copy.aboutRowInstallDetail()) {
                    Toggle(Copy.aboutRowInstall(), isOn: Binding(get: { updater.installsAutomatically }, set: { updater.installsAutomatically = $0 }))
                        .labelsHidden().toggleStyle(.switch).disabled(updater.isRunning == false || updater.checksAutomatically == false)
                }
                SettingsStackedRow(id: "update-delay", title: Copy.aboutRowDelay(), detail: Copy.aboutRowDelayDetail()) {
                    SegmentedChoice(
                        options: updateDelayChoices.map { (value: $0, title: Copy.updatesDelay(days: $0), icon: nil) },
                        selection: Binding(get: { clampedUpdateDelay(delay) }, set: { delay = $0 })
                    )
                    .accessibilityLabel(Copy.aboutRowDelay()).disabled(updater.isRunning == false)
                }
            }
            SettingsGroup(id: "engine", title: Copy.aboutGroupEngine()) {
                SettingsTabRow(id: "engine-and-chat-host", title: Copy.aboutRowEngine(), detail: engine.line(), first: true) {
                    HStack(spacing: Tokens.Space.s10) {
                        switch engine {
                        case .running: ProgressView().controlSize(.mini).frame(width: 16, height: 16).accessibilityLabel(Copy.updatesUpdating())
                        case .upToDate, .updated: StatusMark(symbol: .check, color: .green, label: Copy.lifecycleEngineUpToDate())
                        case .failed: StatusMark(symbol: .close, color: .orange, label: Copy.aboutEngineFailed())
                        case .unknown: EmptyView()
                        }
                        if engine.canRetry {
                            Button { ChatHostStarter.shared.retryUpgrade() } label: { Label(Copy.aboutTryAgain(), icon: .refresh) }
                                .buttonStyle(SecondaryCapsuleButtonStyle())
                        }
                    }
                }
                if let notice = engine.notice {
                    Text(notice.line).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).copyOnHover(notice.line)
                        .padding(.vertical, Tokens.Space.s10)
                }
            }
        }
    }
}
