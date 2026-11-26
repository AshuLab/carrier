import AppKit
import CarrierCore
import CarrierUI
import SwiftUI

/// The Watching page: the repos Carrier takes epics from (the `repos` of `engine.json`, `CarrierCore/RepoList.swift`; their order and summary are
/// `CarrierCore/WatchingList.swift`), each with how its last check went. A row opens the repo's own screen, a place of the window's history: its status,
/// whether Carrier can work in it, who works there and Stop watching. Watch a project picks one of the Projects. Saved like the Behavior tab: every change
/// is sent to the engine as it is made (`setWatchedRepos`, which writes `engine.json` and makes the engine run on it), and nothing restarts Carrier.
struct WatchingTabView: View {
    private let timeChanges = TimeFormatChanges()
    /// Where the page is: nothing for the list, or the `owner/name` of a repo.
    var place = SettingsPlace(.watching)
    var go: (SettingsPlace) -> Void = { _ in }
    let state: ConnectionState?
    let canReload: Bool
    /// Open Roles: the page of the global roles, which every repo inherits.
    let openRoles: () -> Void
    @ObservedObject private var start = StartController.shared
    @State private var saved: [String] = []
    @State private var draft: [String] = []
    @State private var unreadable = false
    /// the file as `load` read it, for the roles on a repo's page
    @State private var configData: Data?
    /// `providers.json`, for the account menus of the roles.
    @State private var providersData: Data?
    @State private var failure: String?
    /// what the engine answered to the last save, from any tab: a refusal means a repo of the list is not in use, whatever the engine can do
    private let reloaded = ReloadStatus.shared
    private let projects = ProjectsModel.shared
    private let sender = EngineConfigSender.app
    /// the request in flight; the next one waits for it, so two changes never reach the file out of order
    @State private var saving: Task<Void, Never>?
    /// the repo whose Stop watching was pressed
    @State private var removing: String?
    /// Watch a project's popover
    @State private var picking = false
    /// the registry of Agent Forge, for the pictures of the roles
    @State private var bots: ForgeBots?
    @Environment(\.settingsHeaderButtons) private var headerButtons
    @State private var owner = UUID()
    private let doctor = AppHealth.doctor

    private var path: String { configFilePath() }

    private var engine: String { engineFolder() }

    private var snapshot: PanelSnapshot? {
        if case .running(let snapshot) = state { return snapshot }
        return nil
    }

    var body: some View {
        let problem = reposProblem(draft)
        let rows = watchingOrder(repoRows(draft: draft, saved: saved, snapshot: snapshot)).map { row in
            var row = row
            row.extras = configData.flatMap { repoRoles(json: $0, repo: row.name) }?.extras ?? .sameAsEverywhere
            return row
        }
        let chosen = place.path.first.flatMap { name in rows.first { $0.name == name } }
        let repoPage = chosen.flatMap { rolesPage(of: $0) }
        let role = place.path.dropFirst().first.flatMap(RoleSlot.init(name:))
        let roleRow = role.flatMap { role in repoPage?.rows.first { $0.slot == role } }
        SettingsPageBody {
            notices
            if let chosen, let roleRow, let page = repoPage {
                roleScreen(chosen, roleRow, page: page)
            } else if let chosen {
                repoScreen(chosen, page: repoPage)
            } else {
                WatchingListScreen(
                    rows: rows, projectName: { project(of: $0)?.name },
                    open: { go(SettingsPlace(.watching, path: [$0.name])) }, watch: { picking = true }
                )
            }
            // the list is written as it changes and says nothing about it, unless it could not, the engine would refuse it or it did not apply it
            if let words = [unreadable ? nil : problem, failure].compactMap({ $0 }).first { SettingsGroup(title: "") { ProblemLine(text: words) } }
            if case .refused? = reloaded.outcome {} else { ReloadNote(reloaded) }
        }
        .buttonStyle(SecondaryCapsuleButtonStyle())
        // nothing to edit until the file reads; it is read again when it appears or goes (`StartController` checks every 3 seconds)
        .disabled(unreadable)
        .overlay(alignment: .topTrailing) {
            // the popover of Watch a project hangs from the top right of the page, under the toolbar's button
            Color.clear.frame(width: 1, height: 1).popover(isPresented: $picking, arrowEdge: .top) { picker }
        }
        .preference(key: SettingsTitleKey.self, value: title(chosen, roleRow))
        .onAppear {
            load()
            projects.reload()
            publishHeader(rows: rows, repo: chosen, role: roleRow)
        }
        .onChange(of: headerButtonsNow(rows: rows, repo: chosen, role: roleRow).map(\.button)) { publishHeader(rows: rows, repo: chosen, role: roleRow) }
        .onChange(of: place) { publishHeader(rows: rows, repo: chosen, role: roleRow) }
        .onDisappear { headerButtons?.clear(owner) }
        // the doctor runs when the page opens and on Check again, never in the background
        .task { runDoctor() }
        .onChange(of: start.configExists) { load() }
        // a file that is there but unreadable may be fixed in another app: look again when Carrier is back in front (only then, so no edit is lost)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            providersData = readProviders()
            if unreadable { load() }
        }
        .onChange(of: draft) {
            autosave()
        }
        .alert(
            Copy.watchingStopAlert(repo: removing ?? ""),
            isPresented: Binding(get: { removing.map { draft.contains($0) } ?? false }, set: { if $0 == false { removing = nil } })
        ) {
            Button(Copy.watchingCancel(), role: .cancel) { removing = nil }
            Button(Copy.watchingStopTitle(), role: .destructive) {
                if let name = removing { draft.removeAll { $0 == name } }
                removing = nil
                go(SettingsPlace(.watching))
            }
        } message: {
            Text(removing.map { removalText(repoEpics($0, snapshot: snapshot), appliesNow: appliesWhileRunning(state: state, canReload: canReload)) } ?? "")
        }
    }

    // MARK: the toolbar

    /// What the toolbar says: a repo's name, or a role's with the repo and its model under it.
    private func title(_ repo: RepoRow?, _ role: RoleRow?) -> SettingsTitle? {
        guard let repo else { return nil }
        if let role { return SettingsTitle(text: role.title(), subtitle: Copy.watchingRoleSubtitle(repo: repo.name, headline: role.headline())) }
        return SettingsTitle(text: repo.name, subtitle: subtitle(repo))
    }

    /// The pills of the toolbar: the list has Check now and Watch a project…; a repo's screen has Open on GitHub and Check again; a role's has none.
    private func headerButtonsNow(rows: [RepoRow], repo: RepoRow?, role: RoleRow?) -> [(button: SettingsHeaderButton, run: () -> Void)] {
        if role != nil { return [] }
        if let repo {
            let checking = doctor.state == .running
            return [
                (SettingsHeaderButton(title: Copy.watchingOpenOnGitHub(), icon: .externalLink), { if let url = repo.gitHubURL { NSWorkspace.shared.open(url) } }),
                (SettingsHeaderButton(title: Copy.watchingCheckAgain(), icon: .refresh, enabled: checking == false, spinning: checking, help: Copy.watchingCheckAgainHelp()), runDoctor),
            ]
        }
        return (rows.isEmpty ? [] : [(SettingsHeaderButton(title: Copy.watchingCheckNow(), icon: .refresh, enabled: snapshot != nil, help: Copy.watchingCheckNowHelp()), { MenuControls.shared.checkNow() })])
            + [(SettingsHeaderButton(title: Copy.watchingWatchProject(), icon: .plus), { picking = true })]
    }

    private func publishHeader(rows: [RepoRow], repo: RepoRow?, role: RoleRow?) {
        headerButtons?.set(owner, headerButtonsNow(rows: rows, repo: repo, role: role))
    }

    /// What is wrong with the engine before anything else: it is not configured, or it refused the saved file and kept the settings it had, so what was saved
    /// is not in use. Any other answer is the note every page ends with.
    @ViewBuilder private var notices: some View {
        if unreadable {
            SettingsGroup(title: "") {
                Label(Copy.engineConfigUnreadable(), icon: .warningFilled)
                    .scaledFont(12).foregroundStyle(.orange)
            }
        }
        if case .refused(let reason)? = reloaded.outcome {
            SettingsGroup(title: "") { RefusalBannerView(banner: refusalBanner(reason)) { go(SettingsPlace($0)) } }
        }
    }

    /// What the toolbar says under a repo's name.
    private func subtitle(_ row: RepoRow) -> String {
        switch row.health {
        case .error: Copy.watchingSubtitle(which: .attention)
        case .ok: Copy.watchingSubtitle(which: .watching)
        case .unknown: snapshot == nil ? Copy.watchingSubtitle(which: .stopped) : Copy.watchingSubtitle(which: .watching)
        }
    }

    // MARK: Watch a project

    private var picker: some View {
        WatchPicker(choices: watchChoices(projects: projects.rows, watched: draft), carrierFolder: projects.carrierFolder) { repo in
            picking = false
            draft.append(repo)
        } addProject: {
            picking = false
            go(SettingsPlace(.projects))
        }
    }

    /// The project whose GitHub origin is this repo, when one is.
    private func project(of row: RepoRow) -> ProjectRow? {
        projects.rows.first { $0.clone == nil && $0.repo?.caseInsensitiveCompare(row.name) == .orderedSame }
    }

    // MARK: a repo's screen

    /// Not awaited: the card says it is running.
    private func runDoctor() { runSettingsDoctor() }

    /// A repo's roles as the repo has them: the global ones with its own over them. nil when the file does not read.
    private func rolesPage(of repo: RepoRow) -> RolesPage? {
        guard let configData, let bots else { return nil }
        return repoRolesPage(config: configData, providers: providersData, bots: bots, repo: repo.name)
    }

    /// The extra reviewers that run in the repo: its own list, or Roles'.
    private func reviewers(of repo: RepoRow) -> [RoleRow] {
        guard let configData, let bots else { return [] }
        return repoExtraReviewers(config: configData, providers: providersData, bots: bots, repo: repo.name) ?? []
    }

    /// The chosen repo's screen. Open on GitHub and Check again are the toolbar's.
    private func repoScreen(_ row: RepoRow, page: RolesPage?) -> some View {
        let status = repoStatus(row, engine: engine, cloneExists: FileManager.default.fileExists(atPath: row.clonePath(engine: engine)), notLoaded: settingsNote(state: state, canReload: canReload, outcome: reloaded.outcome))
        let owner = project(of: row)
        let roles = configData.flatMap { repoRoles(json: $0, repo: row.name) }
        return RepoScreen(
            row: row, status: status, project: owner?.name,
            checks: repoChecks(repo: row.name, roles: roles?.rows ?? [], doctor: doctor.state), checking: doctor.state == .running,
            roles: page.flatMap { page in
                roles.map { (page: page, own: Set($0.rows.filter(\.isOwn).map { RoleSlot($0.role) }), extras: $0.extras, reviewers: reviewers(of: row)) }
            },
            icons: accountIcons(providersJSON: providersData), refusal: refusal,
            openProject: { owner.map { go(SettingsPlace(.projects, path: [$0.path])) } ?? go(SettingsPlace(.projects)) },
            openRole: { go(SettingsPlace(.watching, path: [row.name, $0.name])) }, stop: { removing = row.name }
        )
    }

    /// A role's screen in the repo.
    @ViewBuilder private func roleScreen(_ repo: RepoRow, _ row: RoleRow, page: RolesPage) -> some View {
        if let role = row.role, let mine = configData.flatMap({ repoRoles(json: $0, repo: repo.name) })?.rows.first(where: { $0.role == role }), let roles = configData.flatMap({ repoRoles(json: $0, repo: repo.name) }) {
            RepoRoleScreen(
                row: row, mine: mine, page: page, profiles: roles.profiles, accounts: declaredAccounts(providersJSON: providersData), icons: accountIcons(providersJSON: providersData),
                save: { await saveRole($0, role: role, repo: repo.name) }, open: { go(SettingsPlace(.watching, path: [repo.name, $0.name])) }
            )
            .id("\(repo.name)/\(row.id)")
        }
    }

    /// The accounts file, read when the page opens and when Carrier comes back to the front, not at each body.
    private func readProviders() -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: CarrierPlaces().providers))
    }

    private var refusal: String? {
        if case .refused(let reason) = doctor.state { return Copy.watchingDoctorRefused(reason: reason) }
        return nil
    }

    /// Sends the role (`editRepoRole`), then reads the file back and asks the doctor, whose reason is shown when the engine refuses what was written.
    private func saveRole(_ fields: RoleFields?, role: AgentRole, repo: String) async -> RoleSave {
        let result = await saveToEngine(.repoRole(repo: repo, role: role, fields: fields))
        if result == .saved {
            failure = nil
            load()
            runDoctor()
        }
        return result
    }

    private func load() {
        providersData = readProviders()
        bots = forgeBots(registry: currentForgeRegistry())
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let names = configRepoNames(json: data) else {
            unreadable = true
            configData = nil
            saved = []
            draft = []
            failure = nil
            return
        }
        unreadable = false
        configData = data
        saved = names
        draft = names
    }

    /// Asks the engine for the list as it is now, after the request before it; false, with the reason shown, when it was refused or could not be asked.
    private func write(_ names: [String]) async -> Bool {
        let result = await saveEngineConfig(.watchedRepos(names), send: sender.send, status: reloaded)
        failure = result.problem
        if result == .saved { saved = names }
        return result == .saved
    }

    /// Sends the list as soon as it changes, when the engine would accept it.
    private func autosave() {
        guard unreadable == false, draft != saved, reposProblem(draft) == nil else { return }
        let names = draft, before = saving
        saving = Task {
            await before?.value
            _ = await write(names)
        }
    }
}
