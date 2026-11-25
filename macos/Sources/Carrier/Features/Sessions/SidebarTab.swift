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
        ("preview-idle", "Fix the flaky login test", SessionState.idle, false, -11, SessionPullRequest?.none),
        ("preview-done", "Add the retry to uploads", .idle, true, -3, SessionPullRequest(number: 412, url: "https://github.com/AshuLab/carrier/pull/412", state: .open, checks: .passing)),
        ("preview-waiting", "Rename the billing module", .waiting, false, -26, nil),
    ].map { id, title, state, unread, minutes, pullRequest in
        SessionRow(
            id: id, title: title, workspace: "carrier", agent: "claude", state: state, updatedAt: Date(timeIntervalSinceNow: Double(minutes) * 60),
            branch: "fix/login-flake", folder: "/preview", providers: ["claude", "codex"], unread: unread,
            diff: pullRequest == nil ? (state == .idle && unread == false ? SessionDiff(added: 12, removed: 3) : nil) : SessionDiff(added: 86, removed: 12), pullRequest: pullRequest
        )
    }

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.sidebar) }) {
            SettingsGroup(id: "order", title: "Order") {
                SettingsTabRow(id: "group-epics-by", title: "Group epics by", detail: "How the epics under Carrier are grouped", first: true) {
                    picker("Group epics by", selection: $groupBy, options: GroupBy.allCases) { $0.title }
                }
                SettingsTabRow(id: "sort-sessions", title: "Sort sessions", detail: "How the Sessions list is grouped and ordered") {
                    picker("Sort sessions", selection: $sessionSort, options: SessionSort.allCases) { $0.title }
                }
                SettingsTabRow(id: "sort-the-archive", title: "Sort the Archive", detail: "How the archived sessions are ordered") {
                    picker("Sort the Archive", selection: $archiveSort, options: ArchiveSort.allCases) { $0.title }
                }
            }
            SettingsGroup(id: "session-rows", title: "Session rows") {
                SettingsTabRow(id: "project-icon", title: "Project icon", detail: "The colored square with the project's initials", first: true) {
                    Toggle("Project icon", isOn: $showsIcon).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "branch", title: "Branch", detail: "Where the session works, the branch or the base folder") {
                    Toggle("Branch", isOn: $showsBranch).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "pull-request", title: "Pull request", detail: "The pull request of the session's branch, with its state and how its checks went, on a third line") {
                    Toggle("Pull request", isOn: $showsPullRequest).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "lines-changed", title: "Lines changed", detail: "How many lines the session added and removed, on the third line with or without a pull request") {
                    Toggle("Lines changed", isOn: $showsDiff).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "providers", title: "Providers", detail: "The marks of the providers the session used") {
                    Toggle("Providers", isOn: $showsProviders).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "age", title: "Age", detail: "How long ago the session was last active; Done and Needs you take its place, and so do Pin and Archive on hover") {
                    Toggle("Age", isOn: $showsAge).labelsHidden().toggleStyle(.switch)
                }
                SettingsPreview {
                    VStack(spacing: 0) {
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
