import AppKit
import CarrierCore
import SwiftUI

/// The Engine page of Settings (docs/specs/engine-in-settings.md), drawn from `engineGroups`: Starting, Programs, GitHub identity and Files. The programs' versions are
/// read once for the whole page, and again when a program or a detection changes.
struct EngineTabView: View {
    @ObservedObject var setup: SetupController
    @ObservedObject private var start = StartController.shared
    @AppStorage(Preference.engineStartOnOpen) private var startOnOpen
    @AppStorage(Preference.stopConfirm) private var confirmStop
    @StateObject private var github = EngineIdentityStore()
    /// What `carrier --version` and `node --version` printed for the programs the page shows; nil while they are being read.
    @State private var versions: ProgramVersions?

    var body: some View {
        // one container, so the versions are read once and not once per group
        SettingsPageBody { engine(notConfigured: engineNotConfiguredNotice(configExists: start.configExists)) }
            .task(id: versionsKey) {
                versions = nil
                versions = await ProgramVersions.read(setup)
            }
    }

    /// Changes when a program the page shows does, and when a detection ends (an upgrade keeps the path), so the versions are read again.
    private var versionsKey: String { "\(setup.carrier ?? "")|\(setup.settings.node)|\(setup.settings.path)|\(setup.detecting)" }

    @ViewBuilder private func engine(notConfigured: String?) -> some View {
        if let notConfigured {
            Label(notConfigured, icon: .warningFilled).scaledFont(12).foregroundStyle(.orange)
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
            SettingsGroup(id: group.id, title: group.title) {
                ForEach(Array(group.rows.enumerated()), id: \.element.title) { index, row in
                    SettingsTabRow(id: row.id.rawValue, title: row.title, detail: row.detail, first: index == 0, note: row.note ?? row.file?.shown, problem: row.problem) {
                        switch row.id {
                        case .startOnOpen: Toggle(row.title, isOn: $startOnOpen).labelsHidden().toggleStyle(.switch).disabled(notConfigured != nil)
                        case .confirmStop: Toggle(row.title, isOn: $confirmStop).labelsHidden().toggleStyle(.switch)
                        case .carrier: CarrierChoice(setup: setup, offersHomebrew: row.offersHomebrew)
                        case .node, .path: EmptyView()
                        case .lookAgain:
                            HStack(spacing: Tokens.Space.s8) {
                                // beside the button, so the button keeps its size and its name while it works
                                if setup.detecting { ProgressView().controlSize(.small).accessibilityLabel(Copy.engineDetecting()) }
                                Button { setup.detect(); start.refreshConfig() } label: { Label(Copy.engineDetect(), icon: .refresh).labelStyle(.titleAndIcon) }
                                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(setup.detecting)
                            }
                            .onChange(of: setup.detecting) { _, detecting in
                                if detecting == false { AccessibilityNotification.Announcement(setup.message ?? Copy.engineDetectionFinished()).post() }
                            }
                        case .orchestratorProfile: identityChoice(row.title)
                        case .carrierFolder, .logs, .startLog:
                            if let file = row.file {
                                Button {
                                    let url = URL(fileURLWithPath: file.path)
                                    if file.action == .reveal { NSWorkspace.shared.activateFileViewerSelecting([url]) } else { NSWorkspace.shared.open(url) }
                                } label: { Label(file.buttonTitle(), icon: file.exists ? (file.action == .reveal ? .folder : .fileText) : .folderQuestion).labelStyle(.titleAndIcon) }
                                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(file.exists == false)
                                    .accessibilityLabel(Copy.engineFileAccessibility(button: file.buttonTitle(), row: row.title))
                            }
                        }
                    }
                }
            }
        }
        ReloadNote(ReloadStatus.shared).padding(.horizontal, Tokens.Space.s4)
    }

    /// The default first, then the profiles of the file; an undeclared one the file names is on the list too (`EngineIdentity.choices`).
    private func identityChoice(_ title: String) -> some View {
        let identity = github.identity
        return ChoicePopUp(
            label: title,
            options: EngineIdentity.options(identity),
            selection: Binding(get: { identity?.current }, set: { if $0 != identity?.current { github.choose($0) } })
        )
        .disabled(identity == nil)
        .onAppear { github.load() }
        .onChange(of: start.configExists) { github.load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in github.load() }
    }
}
