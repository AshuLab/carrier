import Foundation
import Testing

@testable import CarrierCore

// The Identities page (docs/macos/settings-carrier.md#identities): every identity a role can sign as, the roles that sign as each (globally and as a
// repo's own role), the repos where each can mint a token from the doctor's checks, and what the row says while the doctor runs or did not answer.

private let fixtureBots = forgeBots(registry: Data(fixtureForgeRegistry.utf8), bundle: english.bundle, locale: english.locale)

private func goldenDoctor() throws -> DoctorState {
    let path = testPaths().fixtures.appendingPathComponent("doctor.json")
    return doctorState(from: ProcessOutcome(exitCode: 1, stdout: String(decoding: try Data(contentsOf: path), as: UTF8.self)))
}

private func page(_ config: String = fixtureConfig, bots: ForgeBots = fixtureBots, doctor: DoctorState = .idle) throws -> IdentitiesPage {
    try #require(identitiesPage(config: Data(config.utf8), bots: bots, doctor: doctor, bundle: english.bundle, locale: english.locale))
}

private func row(_ key: String, in page: IdentitiesPage) throws -> IdentityRow { try #require(page.rows.first { $0.id == key }) }

private func signs(_ row: IdentityRow) -> [String] { row.signsAs.map { $0.title(bundle: english.bundle, locale: english.locale) } }

@Test func theListIsTheBotsOfTheRegistryInTheirOrderAndThenTheGhLogin() throws {
    let found = try page()
    #expect(found.rows.map(\.id) == ["bot:acme-author", "bot:acme-reviewer", "bot:acme-lead", "bot:acme-spare", "gh"])
    #expect(found.rows.map { $0.title(bundle: english.bundle, locale: english.locale) } == ["acme-author", "acme-reviewer", "acme-lead", "acme-spare", "Your gh login"])
    #expect(found.rows.map { $0.kind(bundle: english.bundle, locale: english.locale) } == Array(repeating: "A bot from Agent Forge", count: 4) + ["Your own account"])
    // the picture comes from the registry's App id: the ones that have none keep their initials
    #expect(found.rows.map(\.appId) == ["1000001", "1000002", nil, nil, nil])
    #expect(found.rows.first?.appLine(bundle: english.bundle, locale: english.locale) == "GitHub App 1000001")
}

@Test func eachRoleIsAChipOfTheIdentityItSignsAsAndAnIdentityNoRoleUsesHasNone() throws {
    let found = try page()
    #expect(signs(try row("bot:acme-author", in: found)) == ["Author"])
    #expect(signs(try row("bot:acme-reviewer", in: found)) == ["Reviewer"])
    #expect(signs(try row("bot:acme-lead", in: found)) == ["Lead reviewer"])
    #expect(try row("bot:acme-spare", in: found).signsAs.isEmpty && row("gh", in: found).signsAs.isEmpty)
}

@Test func theLeadReviewerSignsOnlyWhileTheFileHasOne() throws {
    let config = fixtureConfig.replacingOccurrences(of: #""leadReviewer": {"profile": "acme-lead", "provider": "claude", "model": "claude-opus-5"}"#, with: "\"x\": 1")
    #expect(try page(config).rows.allSatisfy { $0.signsAs.allSatisfy { $0.role != .leadReviewer } })
}

@Test func aRepoOwnRoleSignsAsItsOwnIdentityAndIsListedWithTheRepo() throws {
    let config = fixtureConfig
        .replacingOccurrences(of: #"{"name": "acme/api", "agents": {"reviewer": {"model": "gpt-5-mini"}}}"#, with: #"{"name": "acme/api", "agents": {"reviewer": {"profile": "acme-spare"}}}"#)
        .replacingOccurrences(of: #""acme-lead": {"kind": "forge", "agent": "acme-lead"}"#, with: #""acme-lead": {"kind": "forge", "agent": "acme-lead"}, "acme-spare": {"kind": "forge", "agent": "acme-spare"}"#)
    let found = try page(config)
    let spare = try row("bot:acme-spare", in: found)
    #expect(signs(spare) == ["Reviewer in acme/api"] && spare.signsAs.first?.repo == "acme/api" && spare.signsAs.first?.role == .reviewer)
    // the global role is still the reviewer's identity everywhere else
    #expect(signs(try row("bot:acme-reviewer", in: found)) == ["Reviewer"])
}

@Test func theGhLoginIsWhicheverProfileOfKindGhARoleNames() throws {
    let config = #"{"profiles": {"me": {"kind": "gh"}, "other": {"kind": "gh"}}, "agents": {"author": {"profile": "me"}, "reviewer": {"profile": "other"}}, "repos": []}"#
    #expect(signs(try row("gh", in: page(config, bots: ForgeBots(names: [])))) == ["Author", "Reviewer"])
}

@Test func aProfileWhoseBotTheRegistryDoesNotHaveBelongsToNoIdentity() throws {
    let found = try page(fixtureConfig, bots: ForgeBots(names: ["acme-author"]))
    #expect(found.rows.map(\.id) == ["bot:acme-author", "gh"] && found.rows.allSatisfy { $0.id == "bot:acme-author" || $0.signsAs.isEmpty })
}

@Test func theGoldenDoctorOutputSaysTheReviewerCannotMintATokenInAcmeApiOnlyAndItsRowSaysSo() throws {
    let found = try page(doctor: try goldenDoctor())
    let reviewer = try row("bot:acme-reviewer", in: found)
    #expect(reviewer.standing == .cannotSign(["acme/api"]))
    #expect(reviewer.standingLine(bundle: english.bundle, locale: english.locale) == "Cannot sign in acme/api")
    #expect(reviewer.repos.map { "\($0.id): \($0.check.status)" } == [
        "acme/web: ok", "acme/api: fail", "acme/a-really-long-repository-name-for-the-sidebar: ok",
    ])
    let failed = try #require(reviewer.repos.first { $0.check.status == .fail })
    #expect(failed.check.detail == "acme-reviewer has no installations on acme/api" && failed.check.fix == "install the GitHub App of that agent on acme")
    // the others can sign everywhere their role works, with the check's own words for the ones that passed
    for key in ["bot:acme-author", "bot:acme-lead"] {
        let ok = try row(key, in: found)
        #expect(ok.standing == .canSign && ok.repos.allSatisfy { $0.check.status == .ok && $0.check.detail == "Can mint a token" }, Comment(rawValue: key))
        #expect(ok.standingLine() == nil)
    }
}

@Test func anIdentityNoRoleUsesInARepoIsNotCheckedThereAndSaysNothingOnItsRow() throws {
    let found = try page(doctor: try goldenDoctor())
    for key in ["bot:acme-spare", "gh"] {
        let unused = try row(key, in: found)
        #expect(unused.standing == .unchecked && unused.repos.count == 3 && unused.repos.allSatisfy { $0.unused && $0.check.status == .waiting }, Comment(rawValue: key))
        #expect(unused.repos.first?.check.detail == "No role signs as it here, so it is not checked")
    }
}

@Test func aRepoWhereTheIdentityWorksButTheDoctorHasNoCheckReadsAsWaitingNeverAsFailed() throws {
    let found = try page(doctor: .checks([]))
    let author = try row("bot:acme-author", in: found)
    #expect(author.standing == .unchecked && author.repos.allSatisfy { $0.check.status == .waiting && $0.check.detail == "Not checked yet" && $0.unused == false })
}

@Test func whileTheDoctorRunsAndWhenItDidNotAnswerEveryRowSaysSoAndThePageSaysWhy() throws {
    let running = try page(doctor: .running)
    #expect(running.rows.allSatisfy { $0.standing == .checking && $0.standingLine(bundle: english.bundle, locale: english.locale) == "Checking…" })
    #expect(running.doctorNote == "Running carrier doctor…")
    let unknown = try page(doctor: .unknown("could not start"))
    #expect(unknown.rows.allSatisfy { $0.standing == .unanswered && $0.standingLine(bundle: english.bundle, locale: english.locale) == "Could not check where it can sign" })
    #expect(unknown.doctorNote == "Could not check: could not start")
    let refused = try page(doctor: .refused("Invalid config"))
    #expect(refused.rows.allSatisfy { $0.standing == .unanswered } && refused.doctorNote == "Carrier refuses the config: Invalid config")
    // before the doctor has run there is nothing to say
    #expect(try page().rows.allSatisfy { $0.standing == .unchecked } && page().doctorNote == nil)
}

@Test func theRegistryNoteIsKeptWhenThereAreNoBotsAndTheGhLoginStays() throws {
    let found = try page(bots: forgeBots(registry: nil, bundle: english.bundle, locale: english.locale))
    #expect(found.rows.map(\.id) == ["gh"] && found.registryNote?.hasPrefix("No Agent Forge registry") == true)
}

@Test func aBotPageIsOnGitHubUnderItsNameAndTheGhLoginHasNone() throws {
    let found = try page()
    #expect(try row("bot:acme-author", in: found).gitHubURL?.absoluteString == "https://github.com/apps/acme-author")
    #expect(try row("gh", in: found).gitHubURL == nil)
    // a name that is not one GitHub accepts never reaches an address
    let odd = try page(#"{"profiles": {}, "agents": {}}"#, bots: ForgeBots(names: ["../evil", "Mixed-Case"]))
    #expect(try row("bot:../evil", in: odd).gitHubURL == nil && row("bot:Mixed-Case", in: odd).gitHubURL?.absoluteString == "https://github.com/apps/mixed-case")
}

@Test func aRoleKnowsItsIdentitiesKeyForTheWindowsHistory() {
    #expect(RoleIdentity.forge("acme-author").key == "bot:acme-author" && RoleIdentity.gh.key == "gh")
    #expect(RoleIdentity.missing.key == nil && RoleIdentity.unset.key == nil)
}

@Test func aFileThatIsNotAnObjectGivesNoPage() {
    #expect(identitiesPage(config: Data("[]".utf8), bots: fixtureBots, doctor: .idle) == nil)
}

@Test func theRowsAndTheirWordsAreInSpanishToo() throws {
    let found = try #require(identitiesPage(config: Data(fixtureConfig.utf8), bots: fixtureBots, doctor: try goldenDoctor(), bundle: spanish.bundle, locale: spanish.locale))
    let reviewer = try row("bot:acme-reviewer", in: found)
    #expect(reviewer.standingLine(bundle: spanish.bundle, locale: spanish.locale) == "No puede firmar en acme/api")
    #expect(reviewer.kind(bundle: spanish.bundle, locale: spanish.locale) == "Un bot de Agent Forge")
    #expect(try row("gh", in: found).title(bundle: spanish.bundle, locale: spanish.locale) == "Tu sesión de gh")
    #expect(reviewer.repos.first?.check.detail == "Puede obtener un token")
    #expect(try row("bot:acme-spare", in: found).repos.first?.check.detail == "Ningún rol firma aquí con ella, así que no se comprueba")
    #expect(SettingsPage.identities.title(bundle: spanish.bundle, locale: spanish.locale) == "Identidades")
}
