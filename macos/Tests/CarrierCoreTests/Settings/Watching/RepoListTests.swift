import Foundation
import Testing
@testable import CarrierCore

private let fixtures = testPaths().fixtures

private func running() throws -> PanelSnapshot {
    try decodeSnapshot(Data(contentsOf: fixtures.appendingPathComponent("snapshot.json")))
}

private let file = Data(#"""
{"keep":"~/work","pollIntervalMinutes":2,"limits":{"maxReviews":7},"profiles":{"a":{"kind":"gh"}},
 "repos":[{"name":"AshuLab/carrier"},{"name":"acme/web","agents":{"author":{"profile":"other-bot"}}},{"name":"vemec/encaja"}]}
"""#.utf8)

@Test(arguments: ["acme/web", "A-b_c.d/e.f-g", "a/..."])
func anOwnerSlashNameIsARepoName(name: String) { #expect(isRepoName(name)) }

@Test(arguments: ["", "acme", "acme/", "/web", "a/b/c", "../web", "acme/..", "./x", "a b/c", "a/b c", "é/x", "a/b\n"])
func anythingElseIsNot(name: String) { #expect(isRepoName(name) == false) }

@Test func aRepoIsRefusedForItsFormatItsNameOrItsFolder() {
    #expect(repoProblem("acme/api", joining: ["acme/web"], bundle: english.bundle, locale: english.locale) == nil)
    #expect(repoProblem("bad name", joining: [], bundle: english.bundle, locale: english.locale) == "bad name must be owner/name")
    #expect(repoProblem("ACME/Web", joining: ["acme/web"], bundle: english.bundle, locale: english.locale) == "ACME/Web is already watched")
    #expect(repoProblem("other/web", joining: ["acme/web"], bundle: english.bundle, locale: english.locale) == "other/web has the same folder name as acme/web; Solve's worktree paths have no owner")
}

@Test func theWholeListHasNoProblemsAndMayBeEmpty() {
    #expect(reposProblem([], bundle: english.bundle, locale: english.locale) == nil)
    #expect(reposProblem(["acme/web", "acme/api"], bundle: english.bundle, locale: english.locale) == nil)
    #expect(reposProblem(["acme/web", "other/web"], bundle: english.bundle, locale: english.locale)?.contains("same folder name as acme/web") == true)
}

@Test func theReposInTheFileAreRead() {
    #expect(configRepoNames(json: file) == ["AshuLab/carrier", "acme/web", "vemec/encaja"])
    #expect(configRepoNames(json: Data("{}".utf8)) == [])
    #expect(configRepoNames(json: Data("[]".utf8)) == nil)
}

@Test func theEpicsOfARepoAreCountedFromTheSnapshot() throws {
    let snapshot = try running()
    #expect(repoEpics("acme/web", snapshot: nil) == nil)
    let totals = Set(snapshot.epics.map(\.repo) + snapshot.queue.map(\.repo)).map { repoEpics($0, snapshot: snapshot)! }
    #expect(totals.map(\.running).reduce(0, +) == snapshot.epics.filter { $0.status == .running }.count)
    #expect(totals.map(\.needsYou).reduce(0, +) == snapshot.epics.filter { $0.status == .needsHuman }.count)
    #expect(totals.map(\.queued).reduce(0, +) == snapshot.queue.count)
    #expect(repoEpics("nobody/nothing", snapshot: snapshot)?.isNone == true)
}

@Test func theLineAndTheConfirmationSayWhatHappensToTheEpics() {
    let some = RepoEpics(running: 0, queued: 2, needsYou: 1)
    #expect(some.line(bundle: english.bundle, locale: english.locale) == "2 queued · 1 needs you" && RepoEpics().line(bundle: english.bundle, locale: english.locale) == "")
    #expect(removalText(some, appliesNow: true, bundle: english.bundle, locale: english.locale) == "It has epics (2 queued, 1 needs you). They stop where they are, untouched, and continue if you add the repository again. Nothing is deleted. It takes effect right away.")
    #expect(removalText(RepoEpics(), appliesNow: true, bundle: english.bundle, locale: english.locale) == "It has no epics. You can add it again whenever you want. It takes effect right away.")
    #expect(removalText(nil, appliesNow: true, bundle: english.bundle, locale: english.locale).hasPrefix("Its epics, if it has any, stop where they are"))
    #expect(removalText(RepoEpics(), appliesNow: false, bundle: english.bundle, locale: english.locale) == "It has no epics. You can add it again whenever you want. Carrier reads the list when it starts.")
}

@Test func theRowsSayHowEachRepoIs() throws {
    var snapshot = try running()
    let name = try #require(snapshot.watched?.first?.repo)
    snapshot.watched = [PanelSnapshot.Watched(repo: name, lastCheckedAt: snapshot.now - 120_000, ok: true, error: nil, agents: snapshot.watched!.first!.agents),
                        PanelSnapshot.Watched(repo: "bad/repo", lastCheckedAt: snapshot.now, ok: false, error: "GitHub refused the profile", agents: snapshot.watched!.first!.agents)]
    let rows = repoRows(draft: [name, "bad/repo", "later/one", "new/repo"], saved: [name, "bad/repo", "later/one"], snapshot: snapshot, bundle: english.bundle, locale: english.locale)
    #expect(rows[0].health == .ok && rows[0].line.hasPrefix("Checked 2m"))
    #expect(rows[1].health == .error && rows[1].line == "GitHub refused the profile")
    #expect(rows[2].health == .unknown && rows[2].line == "Not in use yet")
    #expect(rows[3].isNew && rows[3].line.hasPrefix("Not checked yet"))

    let stopped = repoRows(draft: ["a/b"], saved: ["a/b"], snapshot: nil, bundle: english.bundle, locale: english.locale)
    #expect(stopped == [RepoRow(name: "a/b", health: .unknown, line: "Carrier is stopped", epics: nil, isNew: false)])
    #expect(stopped[0].owner == "a" && stopped[0].repo == "b" && stopped[0].gitHubURL?.absoluteString == "https://github.com/a/b")
    #expect(stopped[0].clonePath(engine: "/data/carrier/engine") == "/data/carrier/engine/repos/a/b")
    #expect(tildePath("/Users/ana/.carrier/engine/repos/a/b", home: "/Users/ana") == "~/.carrier/engine/repos/a/b" && tildePath("/srv/x", home: "/Users/ana") == "/srv/x")
}

// MARK: the Carrier switch of a project (docs/specs/projects.md, "The watch")

private let names = ["AshuLab/carrier", "acme/web", "vemec/encaja"]

@Test func turningTheSwitchOnAsksForTheListWithTheRepoAddedAndOnceWhateverTheCaseGitHubGaveIt() {
    #expect(watchChange(true, repo: "new/thing", in: names) == .send(names + ["new/thing"]))
    // already watched, whatever the case GitHub gave it: nothing is added twice
    #expect(watchChange(true, repo: "ACME/Web", in: names) == .send(names))
}

@Test func turningTheSwitchOffAsksForTheListWithoutOnlyThatEntry() {
    #expect(watchChange(false, repo: "Acme/Web", in: names) == .send(["AshuLab/carrier", "vemec/encaja"]))
}

@Test func twoWatchedReposWithOneFolderNameAreRefusedWithTheReasonAndNothingIsAsked() {
    #expect(watchChange(true, repo: "other/web", in: names) == .refused("other/web has the same folder name as acme/web; Solve's worktree paths have no owner"))
    // a list that is already invalid is refused whatever is asked
    #expect(watchChange(false, repo: "x/y", in: ["a/web", "b/web"]) == .refused("b/web has the same folder name as a/web; Solve's worktree paths have no owner"))
}

@Test func theSwitchRowSaysWhatIsOnAndWhyNot() throws {
    let on = projectWatchRow(repo: "acme/web", repos: ["Acme/Web"], state: .running(try running()), canReload: true, outcome: .applied, failure: nil)
    #expect(on == ProjectWatchRow(isOn: true, canChange: true, detail: "Carrier applies acme/web to the next epic", problem: nil))
    let off = projectWatchRow(repo: "acme/web", repos: ["x/y"], state: .running(try running()), canReload: true, outcome: nil, failure: nil)
    #expect(off.isOn == false && off.canChange && off.detail == "Carrier does not look for epics in acme/web." && off.problem == nil)
    // a project with no GitHub origin: off, cannot be changed, and says why
    let local = projectWatchRow(repo: nil, repos: ["x/y"], state: .running(try running()), canReload: true, outcome: nil, failure: nil)
    #expect(local.isOn == false && local.canChange == false && local.detail.hasPrefix("No GitHub origin"))
}

@Test func withCarrierStoppedTheRowSaysItReadsTheListWhenItStarts() {
    let on = projectWatchRow(repo: "acme/web", repos: ["acme/web"], state: .stopped, canReload: false, outcome: .nobody, failure: nil)
    #expect(on.detail == "Carrier reads acme/web when it starts" && on.problem == nil)
    let off = projectWatchRow(repo: "acme/web", repos: [], state: .stopped, canReload: false, outcome: nil, failure: nil)
    #expect(off.detail == "Carrier does not look for epics in acme/web. Carrier reads the list when it starts.")
}

@Test func aRefusedChangeOrAnInvalidConfigIsAnOrangeProblemOnTheRow() throws {
    let refused = projectWatchRow(repo: "a/web", repos: ["a/web"], state: .running(try running()), canReload: true, outcome: .refused(.words("repos.0.name: bad")), failure: nil)
    #expect(refused.problem == "Saved, but Carrier kept its settings: repos.0.name: bad")
    let failed = projectWatchRow(repo: "a/web", repos: [], state: .running(try running()), canReload: true, outcome: nil, failure: "other/web has the same folder name as a/web; Solve's worktree paths have no owner")
    #expect(failed.problem?.hasPrefix("other/web has the same folder name") == true)
    let invalid = projectWatchRow(repo: "c/web", repos: ["a/web", "b/web"], state: .running(try running()), canReload: true, outcome: nil, failure: nil)
    #expect(invalid.problem == "b/web has the same folder name as a/web; Solve's worktree paths have no owner")
    let unreadable = projectWatchRow(repo: "a/web", repos: nil, state: .stopped, canReload: false, outcome: nil, failure: nil)
    #expect(unreadable.canChange == false && unreadable.problem?.hasPrefix("The engine is not configured") == true)
}
