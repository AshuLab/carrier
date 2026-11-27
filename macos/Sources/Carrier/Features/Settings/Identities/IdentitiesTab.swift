import AppKit
import CarrierCore
import CarrierUI
import SwiftUI

/// The Identities page of Settings (docs/macos/settings-carrier.md#identities), two kinds of screen, each a place of the window's history (‹ ›): the list of
/// every GitHub profile a role can sign as (the bots of the Agent Forge registry and the person's own gh login) with the roles that sign as each, and one
/// identity's own screen (`SettingsPlace(.identities, path: [key])`, `RoleIdentity.key`). It reads `engine.json`, the registry and the doctor's checks
/// (`identitiesPage`, tested in `IdentitiesPageTests`) and writes nothing: a role picks its identity on its own screen. The doctor runs when the page opens,
/// as Watching runs it, never in the background. The page has no automated test.
struct IdentitiesTabView: View {
    /// Where the page is: nothing for the list, or the key of an identity.
    var place = SettingsPlace(.identities)
    var go: (SettingsPlace) -> Void = { _ in }
    @ObservedObject private var start = StartController.shared
    /// the file and the registry as `load` read them; nil while the file does not read
    @State private var configData: Data?
    @State private var bots: ForgeBots?
    private let doctor = AppHealth.doctor

    private var page: IdentitiesPage? {
        guard let configData, let bots else { return nil }
        return identitiesPage(config: configData, bots: bots, doctor: doctor.state)
    }

    var body: some View {
        let page = page
        let chosen = place.path.first.flatMap { key in page?.rows.first { $0.id == key } }
        SettingsPageBody {
            if let page {
                if let chosen { screen(chosen, page: page) } else { list(page) }
                ReloadNote(ReloadStatus.shared)
            } else {
                Label(Copy.engineConfigUnreadable(), icon: .warningFilled)
                    .scaledFont(12).foregroundStyle(.orange)
            }
        }
        .id(chosen?.id)
        .preference(key: SettingsTitleKey.self, value: chosen.map { SettingsTitle(text: $0.title(), subtitle: $0.kind()) })
        .onAppear(perform: load)
        // the doctor runs when the page opens, never in the background
        .task { runSettingsDoctor() }
        .onChange(of: start.configExists) { load() }
        // back from Terminal, where a bot was created, or an editor, where the config may have changed
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in load() }
    }

    private func load() {
        configData = currentConfig()
        bots = forgeBots(registry: currentForgeRegistry())
    }

    // MARK: the list

    @ViewBuilder private func list(_ page: IdentitiesPage) -> some View {
        let footer = [page.registryNote ?? Copy.identitiesFooter(), page.doctorNote].compactMap { $0 }.joined(separator: "\n")
        SettingsGroup(id: "who-signs", title: Copy.identitiesGroupWho(), footer: footer) {
            ForEach(Array(page.rows.enumerated()), id: \.element.id) { index, row in
                IdentityListRow(row: row, first: index == 0) { go(SettingsPlace(.identities, path: [row.id])) }
            }
            CreateBotRow()
        }
    }

    // MARK: an identity's screen

    @ViewBuilder private func screen(_ row: IdentityRow, page: IdentitiesPage) -> some View {
        let checking = doctor.state == .running
        SettingsGroup(title: "") { IdentityHero(row: row) }
        SettingsGroup(id: "signs-as", title: Copy.identitiesGroupSignsAs()) {
            if row.signsAs.isEmpty {
                SettingsTabRow(title: Copy.identitiesNoRole(), detail: Copy.identitiesNoRoleSigns(), first: true) { EmptyView() }
            }
            ForEach(Array(row.signsAs.enumerated()), id: \.element.id) { index, link in
                NavigationRow(title: link.title(), detail: link.detail(), first: index == 0, action: { open(link) }) { EmptyView() }
            }
        }
        if row.repos.isEmpty == false {
            SettingsGroup(id: "can-sign-in", title: Copy.identitiesGroupCanSign(), footer: page.doctorNote) {
                ForEach(Array(row.repos.enumerated()), id: \.element.id) { index, repo in
                    repoRow(repo, first: index == 0, checking: checking)
                }
            }
        }
        if let url = row.gitHubURL {
            SettingsGroup(title: "") {
                SettingsTabRow(id: "open-on-github", title: Copy.identitiesOpenOnGitHub(), detail: Copy.identitiesOpenOnGitHubDetail(), first: true) {
                    Button { NSWorkspace.shared.open(url) } label: { Label(Copy.identitiesOpenOnGitHub(), icon: .externalLink) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                }
            }
        }
    }

    /// A role that signs as the identity opens its screen: Roles' own, or the repo's for a role (or a list of extra reviewers) the repo has of its own.
    private func open(_ link: IdentityRoleLink) { go(link.place) }

    /// One watched repo: whether the identity can mint a token there, with what the doctor said and its fix when it cannot.
    private func repoRow(_ repo: IdentityRepo, first: Bool, checking: Bool) -> some View {
        let check = repo.check
        let wrong = check.status == .ok || check.status == .waiting ? nil : [check.detail, check.fix.map { Copy.watchingFix(fix: $0) }].compactMap { $0 }.joined(separator: " ")
        let detail = check.status == .waiting && repo.unused == false ? (checking ? Copy.watchingChecking() : Copy.watchingWaiting()) : check.detail ?? ""
        return SettingsTabRow(
            title: check.title, detail: check.status == .fail ? "" : detail, first: first, problem: wrong, wrapsDetail: true,
            leading: AnyView(CheckMark(status: check.status, spinning: checking && repo.unused == false))
        ) { EmptyView() }
    }
}

/// An identity of the list: its picture, name and kind, the roles that sign as it as chips ("No role" when none does) and, in orange under its kind, where
/// it cannot mint a token; a button that opens its screen.
private struct IdentityListRow: View {
    let row: IdentityRow
    let first: Bool
    let open: () -> Void

    var body: some View {
        NavigationRow(
            title: row.title(), detail: detail, leading: IdentityAvatar(row: row, size: 38), first: first,
            problem: problem, action: open
        ) {
            FlowLayout(spacing: Tokens.Space.s4) {
                if row.signsAs.isEmpty {
                    StatusChip(text: Copy.identitiesNoRole(), tint: .secondary)
                } else {
                    ForEach(row.signsAs) { StatusChip(text: $0.title(), tint: .blue) }
                }
            }
            .frame(maxWidth: 280, alignment: .trailing)
        }
    }

    /// Where it cannot mint a token, in orange, in the place of the kind.
    private var problem: String? {
        if case .cannotSign = row.standing { row.standingLine() } else { nil }
    }

    /// The kind, and while the doctor runs or could not answer, that.
    private var detail: String { [row.kind(), row.standing == .checking || row.standing == .unanswered ? row.standingLine() : nil].compactMap { $0 }.joined(separator: " \u{00b7} ") }
}

/// An identity's picture as the roles draw it, with no account in its corner.
private struct IdentityAvatar: View {
    let row: IdentityRow
    let size: CGFloat

    var body: some View { RoleAvatar(identity: row.identity, appId: row.appId, size: size) }
}

/// The top of an identity's screen: its picture, name, kind and, for a bot, its GitHub App id.
private struct IdentityHero: View {
    let row: IdentityRow

    var body: some View {
        HStack(spacing: Tokens.Space.s16) {
            IdentityAvatar(row: row, size: 64)
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text(row.title()).scaledFont(16, weight: .bold).lineLimit(1).truncationMode(.middle)
                Text(row.kind()).scaledFont(12).foregroundStyle(.secondary).lineLimit(1)
                if let app = row.appLine() { Text(app).scaledFont(11.5, design: .monospaced).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled) }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, Tokens.Space.s6)
        .accessibilityElement(children: .combine)
    }
}
