import CarrierCore
import CarrierUI
import SwiftUI

/// A repository's screen, a group for each thing it says or does, in the order of what a person comes here for: how it stands (Status), whether Carrier can work in
/// it (Ready for Carrier), who works there (the rail of Roles, each role opening its own screen), what it is (the project, the clone, GitHub) and, last and apart,
/// Stop watching. Open on GitHub and Check again are the toolbar's.
struct RepoScreen: View {
    let row: RepoRow
    let status: RepoStatus
    /// The name of the project whose origin is this repository; nil when none is.
    let project: String?
    let checks: RepoChecks
    let checking: Bool
    /// The repository's roles as it has them, and the ones it has settings of its own for; nil while the file does not read.
    let roles: (page: RolesPage, own: Set<RoleSlot>)?
    let icons: [String: String]
    /// The doctor's refusal of the config, said under Who works here.
    let refusal: String?
    let openProject: () -> Void
    let openRole: (RoleSlot) -> Void
    let stop: () -> Void

    var body: some View {
        SettingsGroup(id: "status", title: Copy.watchingGroupStatus()) {
            if let note = status.note {
                SettingsTabRow(id: "epics", title: Copy.watchingEpics(), detail: note, first: true) { EmptyView() }
            } else {
                SettingsTabRow(id: "epics", title: Copy.watchingEpics(), detail: epics, first: true) { EmptyView() }
                SettingsTabRow(id: "last-check", title: Copy.watchingLastCheck(), detail: row.health == .error ? "" : status.lastCheck ?? "", problem: row.health == .error ? status.lastCheck : nil) { EmptyView() }
            }
        }
        SettingsGroup(id: "ready-for-carrier", title: Copy.watchingGroupReady(), footer: checking ? nil : checks.note) {
            ForEach(Array(checks.rows.enumerated()), id: \.element.id) { index, check in
                checkRow(check, first: index == 0)
            }
        }
        if let roles {
            SettingsGroup(id: "who-works-here", title: Copy.watchingGroupWho(), footer: refusal ?? Copy.watchingWhoFooter()) {
                EpicRail(page: roles.page, readiness: rolesReadiness(roles.page), icons: icons, own: roles.own, open: openRole)
            }
        }
        SettingsGroup(id: "repository", title: Copy.watchingGroupRepository()) {
            SettingsTabRow(id: "project", title: Copy.watchingProject(), detail: project ?? Copy.watchingNotAProject(), first: true) {
                Button(project == nil ? Copy.watchingAddProject() : Copy.watchingOpenProject(), action: openProject).controlSize(.small)
            }
            SettingsTabRow(id: "clone", title: Copy.watchingClone(), detail: tildePath(status.clonePath), mono: true) {
                if status.canRevealClone {
                    Button(Copy.watchingReveal()) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: status.clonePath)]) }.controlSize(.small)
                }
            }
            SettingsTabRow(id: "on-github", title: Copy.watchingOnGitHub(), detail: status.gitHubURL.map { "github.com\($0.path)" } ?? "", mono: true) { EmptyView() }
        }
        SettingsGroup(title: "") {
            SettingsTabRow(id: "stop-watching", title: Copy.watchingStopTitle(), detail: Copy.watchingStopDetail(), first: true) {
                Button(role: .destructive, action: stop) { Label(Copy.watchingStopButton(), icon: .trash) }.controlSize(.small)
            }
        }
    }

    /// What the repository has in flight, with a word for none.
    private var epics: String {
        guard let epics = row.epics, epics.isNone == false else { return Copy.watchingNone() }
        return epics.line(separator: ", ")
    }

    /// One check of the doctor: its mark at the left, the title, and under it what is wrong with the fix in orange, or how the check stands.
    private func checkRow(_ check: RepoCheckRow, first: Bool) -> some View {
        let wrong = check.status == .ok || check.status == .waiting ? nil : [check.detail, check.fix.map { Copy.watchingFix(fix: $0) }].compactMap { $0 }.joined(separator: " ")
        let detail = check.status == .waiting ? (checking ? Copy.watchingChecking() : Copy.watchingWaiting()) : check.status == .ok ? (check.detail ?? "") : ""
        return SettingsTabRow(title: check.title, detail: detail, first: first, problem: wrong, wrapsDetail: true, leading: AnyView(mark(check.status))) {
            if let role = check.anotherIdentity {
                Button(Copy.watchingUseAnotherIdentity()) { openRole(RoleSlot(role)) }.controlSize(.small)
            }
        }
    }

    private func mark(_ status: RepoCheckRow.Status) -> some View {
        // a row still waiting while the doctor runs turns instead of showing the grey dots
        if status == .waiting && checking {
            return AnyView(ProgressView().controlSize(.mini).frame(width: 16, height: 16).accessibilityLabel(Copy.watchingMark(which: .checking)))
        }
        let (symbol, color, label): (AppIcon, Color, String) = switch status {
        case .ok: (.check, .green, Copy.watchingMark(which: .ok))
        case .warn: (.exclamation, .yellow, Copy.watchingMark(which: .warn))
        case .fail: (.close, .orange, Copy.watchingMark(which: .fail))
        case .waiting: (.dots, .gray, Copy.watchingMark(which: .waiting))
        }
        return AnyView(StatusMark(symbol: symbol, color: color, label: label))
    }
}
