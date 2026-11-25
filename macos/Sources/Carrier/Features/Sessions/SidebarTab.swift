import CarrierCore
import SwiftUI

/// The sidebar's grouping and sorts, which its own menus change too (one preference, two controls), and what each session row shows.
struct SidebarTabView: View {
    @AppStorage(Preference.sidebarGroupBy) private var groupBy
    @AppStorage(Preference.sidebarSessionSort) private var sessionSort
    @AppStorage(Preference.sidebarArchiveSort) private var archiveSort
    @AppStorage(Preference.sidebarRowIcon) private var showsIcon
    @AppStorage(Preference.sidebarRowBranch) private var showsBranch
    @AppStorage(Preference.sidebarRowPullRequest) private var showsPullRequest
    @AppStorage(Preference.sidebarRowDiff) private var showsDiff
    @AppStorage(Preference.sidebarRowProviders) private var showsProviders
    @AppStorage(Preference.sidebarRowAge) private var showsAge

    /// Sessions of the preview: each has a branch, two providers and an age, so each switch has something to hide; one is finished and one waits,
    /// which is where "Done" and "Needs you" take the age's place, and one has a pull request and one only the lines it changed: each gives the row its third line.
    private static let samples = [
        ("preview-idle", Copy.sidebarSettingsSampleIdle(), SessionState.idle, false, -11, SessionPullRequest?.none),
        ("preview-done", Copy.sidebarSettingsSampleDone(), .idle, true, -3, SessionPullRequest(number: 412, url: "https://github.com/AshuLab/carrier/pull/412", state: .open, checks: .passing)),
        ("preview-waiting", Copy.sidebarSettingsSampleWaiting(), .waiting, false, -26, nil),
    ].map { id, title, state, unread, minutes, pullRequest in
        SessionRow(
            id: id, title: title, workspace: "carrier", agent: "claude", state: state, updatedAt: Date(timeIntervalSinceNow: Double(minutes) * 60),
            branch: "fix/login-flake", folder: "/preview", providers: ["claude", "codex"], unread: unread,
            diff: pullRequest == nil ? (state == .idle && unread == false ? SessionDiff(added: 12, removed: 3) : nil) : SessionDiff(added: 86, removed: 12), pullRequest: pullRequest
        )
    }

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.sidebar) }) {
            SettingsGroup(id: "order", title: Copy.sidebarSettingsOrder()) {
                SettingsTabRow(id: "group-epics-by", title: Copy.sidebarGroupEpicsBy(), detail: Copy.sidebarSettingsGroupEpicsByDetail(), first: true) {
                    picker(Copy.sidebarGroupEpicsBy(), selection: $groupBy, options: GroupBy.allCases) { $0.title }
                }
                SettingsTabRow(id: "sort-sessions", title: Copy.sessionsSort(), detail: Copy.sidebarSettingsSortSessionsDetail()) {
                    picker(Copy.sessionsSort(), selection: $sessionSort, options: SessionSort.allCases) { $0.title }
                }
                SettingsTabRow(id: "sort-the-archive", title: Copy.sidebarSettingsSortArchive(), detail: Copy.sidebarSettingsSortArchiveDetail()) {
                    picker(Copy.sidebarSettingsSortArchive(), selection: $archiveSort, options: ArchiveSort.allCases) { $0.title }
                }
            }
            SettingsGroup(id: "session-rows", title: Copy.sidebarSettingsSessionRows()) {
                SettingsTabRow(id: "project-icon", title: Copy.sidebarSettingsProjectIcon(), detail: Copy.sidebarSettingsProjectIconDetail(), first: true) {
                    Toggle(Copy.sidebarSettingsProjectIcon(), isOn: $showsIcon).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "branch", title: Copy.sidebarSettingsBranch(), detail: Copy.sidebarSettingsBranchDetail()) {
                    Toggle(Copy.sidebarSettingsBranch(), isOn: $showsBranch).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "pull-request", title: Copy.sidebarSettingsPullRequest(), detail: Copy.sidebarSettingsPullRequestDetail()) {
                    Toggle(Copy.sidebarSettingsPullRequest(), isOn: $showsPullRequest).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "lines-changed", title: Copy.sidebarSettingsLinesChanged(), detail: Copy.sidebarSettingsLinesChangedDetail()) {
                    Toggle(Copy.sidebarSettingsLinesChanged(), isOn: $showsDiff).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "providers", title: Copy.sidebarSettingsProviders(), detail: Copy.sidebarSettingsProvidersDetail()) {
                    Toggle(Copy.sidebarSettingsProviders(), isOn: $showsProviders).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "age", title: Copy.sidebarSettingsAge(), detail: Copy.sidebarSettingsAgeDetail()) {
                    Toggle(Copy.sidebarSettingsAge(), isOn: $showsAge).labelsHidden().toggleStyle(.switch)
                }
                SettingsPreview {
                    VStack(spacing: Tokens.Space.none) {
                        ForEach(Self.samples, id: \.id) { SessionRowView(row: $0, showsWorkspace: true, roomy: true).allowsHitTesting(false) }
                    }
                }
            }
        }
    }

    private func picker<Value: Hashable>(_ name: String, selection: Binding<Value>, options: [Value], title: @escaping (Value) -> String) -> some View {
        ChoicePopUp(label: name, options: options.map { (value: $0, title: title($0)) }, selection: selection)
    }
}
