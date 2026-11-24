import Foundation
import Testing
@testable import CarrierCore

private let fixtures = testPaths().fixtures

private func running() throws -> PanelSnapshot {
    try decodeSnapshot(Data(contentsOf: fixtures.appendingPathComponent("snapshot.json")))
}

private func object(_ data: Data?) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any] ?? [:]
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
    #expect(repoProblem("acme/api", joining: ["acme/web"]) == nil)
    #expect(repoProblem("bad name", joining: []) == "bad name must be owner/name")
    #expect(repoProblem("ACME/Web", joining: ["acme/web"]) == "ACME/Web is already watched")
    #expect(repoProblem("other/web", joining: ["acme/web"]) == "other/web has the same folder name as acme/web; Solve's worktree paths have no owner")
}

@Test func theWholeListHasNoProblemsAndMayBeEmpty() {
    #expect(reposProblem([]) == nil)
    #expect(reposProblem(["acme/web", "acme/api"]) == nil)
    #expect(reposProblem(["acme/web", "other/web"])?.contains("same folder name as acme/web") == true)
}

@Test func theReposInTheFileAreRead() {
    #expect(configRepoNames(json: file) == ["AshuLab/carrier", "acme/web", "vemec/encaja"])
    #expect(configRepoNames(json: Data("{}".utf8)) == [])
    #expect(configRepoNames(json: Data("[]".utf8)) == nil)
}

@Test func applyingKeepsEachKeptReposOwnFieldsAndTheRestOfTheFile() throws {
    let written = object(applyingRepos(["acme/web", "AshuLab/carrier", "acme/new"], to: file))
    let repos = try #require(written["repos"] as? [[String: Any]])
    #expect(repos.map { $0["name"] as? String } == ["acme/web", "AshuLab/carrier", "acme/new"])
    // the override of acme/web is untouched, and a new repo is only its name
    #expect((repos[0]["agents"] as? [String: Any])?["author"] as? [String: String] == ["profile": "other-bot"])
    #expect(repos[1].keys.sorted() == ["name"] && repos[2].keys.sorted() == ["name"])
    #expect(written["keep"] as? String == "~/work" && written["pollIntervalMinutes"] as? Int == 2)
    #expect((written["limits"] as? [String: Any])?["maxReviews"] as? Int == 7 && written["profiles"] != nil)
}

@Test func theAppNeverMakesAConfigFileNorWritesAnInvalidList() {
    #expect(applyingRepos(["a/b"], to: Data()) == nil)
    #expect(applyingRepos(["a/b"], to: Data("[]".utf8)) == nil)
    #expect(applyingRepos(["acme/web", "other/web"], to: file) == nil)
}

@Test func stoppingToWatchTheLastRepoWritesAnEmptyList() throws {
    let data = try #require(applyingRepos([], to: file))
    let written = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect((written["repos"] as? [Any])?.isEmpty == true && written["profiles"] != nil)
}

@Test func theBehaviorTabAndTheReposTabKeepEachOthersKeys() throws {
    var config = EngineConfig(json: file)
    config.maxConcurrentEpics = 6
    let afterBehavior = try #require(config.applied(to: file))
    #expect(configRepoNames(json: afterBehavior) == ["AshuLab/carrier", "acme/web", "vemec/encaja"])
    #expect((object(afterBehavior)["repos"] as? [[String: Any]])?[1]["agents"] != nil)

    let afterRepos = try #require(applyingRepos(["acme/web"], to: afterBehavior))
    let engine = EngineConfig(json: afterRepos)
    #expect(engine.maxConcurrentEpics == 6 && engine.maxReviews == 7 && engine.pollIntervalMinutes == 2)
    #expect(configRepoNames(json: afterRepos) == ["acme/web"])
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
    #expect(some.line() == "2 queued · 1 needs you" && RepoEpics().line() == "")
    #expect(removalText(some, appliesNow: true) == "It has epics (2 queued, 1 needs you). They stop where they are, untouched, and continue if you add the repository again. Nothing is deleted. It takes effect right away.")
    #expect(removalText(RepoEpics(), appliesNow: true) == "It has no epics. You can add it again whenever you want. It takes effect right away.")
    #expect(removalText(nil, appliesNow: true).hasPrefix("Its epics, if it has any, stop where they are"))
    #expect(removalText(RepoEpics(), appliesNow: false) == "It has no epics. You can add it again whenever you want. Carrier reads the list when it starts.")
}

@Test func theRowsSayHowEachRepoIs() throws {
    var snapshot = try running()
    let name = try #require(snapshot.watched?.first?.repo)
    snapshot.watched = [PanelSnapshot.Watched(repo: name, lastCheckedAt: snapshot.now - 120_000, ok: true, error: nil, agents: snapshot.watched!.first!.agents),
                        PanelSnapshot.Watched(repo: "bad/repo", lastCheckedAt: snapshot.now, ok: false, error: "GitHub refused the profile", agents: snapshot.watched!.first!.agents)]
    let rows = repoRows(draft: [name, "bad/repo", "later/one", "new/repo"], saved: [name, "bad/repo", "later/one"], snapshot: snapshot)
    #expect(rows[0].health == .ok && rows[0].line.hasPrefix("Checked 2m"))
    #expect(rows[1].health == .error && rows[1].line == "GitHub refused the profile")
    #expect(rows[2].health == .unknown && rows[2].line == "Not in use yet")
    #expect(rows[3].isNew && rows[3].line.hasPrefix("Not checked yet"))

    let stopped = repoRows(draft: ["a/b"], saved: ["a/b"], snapshot: nil)
    #expect(stopped == [RepoRow(name: "a/b", health: .unknown, line: "Carrier is stopped", epics: nil, isNew: false)])
    #expect(stopped[0].owner == "a" && stopped[0].repo == "b" && stopped[0].gitHubURL?.absoluteString == "https://github.com/a/b")
    #expect(stopped[0].clonePath(engine: "/data/carrier/engine") == "/data/carrier/engine/repos/a/b")
    #expect(tildePath("/Users/ana/.carrier/engine/repos/a/b", home: "/Users/ana") == "~/.carrier/engine/repos/a/b" && tildePath("/srv/x", home: "/Users/ana") == "/srv/x")
}

// MARK: the Carrier switch of a project (docs/specs/projects.md, "The watch")

private func temporaryConfig(_ data: Data = file) throws -> String {
    let path = NSTemporaryDirectory() + "carrier-watch-\(UUID().uuidString).json"
    try data.write(to: URL(fileURLWithPath: path))
    return path
}

@Test func turningTheSwitchOnAddsTheRepoKeepingEveryOtherKeyAndAsksTheEngineToReload() throws {
    let path = try temporaryConfig()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let engine = FakeReload(file: path)
    #expect(saveWatch(true, repo: "new/thing", path: path, reload: engine.reload) == .saved)
    let written = try #require(engine.now)
    #expect(configRepoNames(json: written) == ["AshuLab/carrier", "acme/web", "vemec/encaja", "new/thing"])
    #expect(object(written)["keep"] as? String == "~/work" && object(written)["profiles"] != nil)
    #expect((object(written)["repos"] as? [[String: Any]])?[1]["agents"] != nil)
    #expect(engine.calls == 1 && engine.seen[0] == written)
    // already watched, whatever the case GitHub gave it: nothing is added twice
    #expect(saveWatch(true, repo: "ACME/Web", path: path, reload: engine.reload) == .saved)
    #expect(configRepoNames(json: try #require(engine.now)) == ["AshuLab/carrier", "acme/web", "vemec/encaja", "new/thing"])
}

@Test func turningTheSwitchOffRemovesOnlyThatEntry() throws {
    let path = try temporaryConfig()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let engine = FakeReload(file: path)
    #expect(saveWatch(false, repo: "Acme/Web", path: path, reload: engine.reload) == .saved)
    #expect(configRepoNames(json: try #require(engine.now)) == ["AshuLab/carrier", "vemec/encaja"])
    #expect(object(engine.now)["keep"] as? String == "~/work" && engine.calls == 1)
}

@Test func twoWatchedReposWithOneFolderNameAreRefusedWithTheReasonAndNothingIsWritten() throws {
    let path = try temporaryConfig()
    defer { try? FileManager.default.removeItem(atPath: path) }
    let engine = FakeReload(file: path)
    let result = saveWatch(true, repo: "other/web", path: path, reload: engine.reload)
    #expect(result == .refused("other/web has the same folder name as acme/web; Solve's worktree paths have no owner"))
    #expect(engine.now == file && engine.calls == 0)
}

@Test func anInvalidOrUnreadableConfigIsNeverWrittenByTheSwitch() throws {
    let invalid = try temporaryConfig(Data(#"{"repos":[{"name":"a/web"},{"name":"b/web"}]}"#.utf8))
    defer { try? FileManager.default.removeItem(atPath: invalid) }
    let engine = FakeReload(file: invalid)
    #expect(saveWatch(false, repo: "x/y", path: invalid, reload: engine.reload).problem == "b/web has the same folder name as a/web; Solve's worktree paths have no owner")
    let notJSON = try temporaryConfig(Data("nope".utf8))
    defer { try? FileManager.default.removeItem(atPath: notJSON) }
    #expect(saveWatch(true, repo: "x/y", path: notJSON, reload: engine.reload) == .failed("The config file could not be read or the list is not valid."))
    #expect(saveWatch(true, repo: "x/y", path: notJSON + ".missing", reload: engine.reload).problem != nil)
    #expect(engine.calls == 0)
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
    let refused = projectWatchRow(repo: "a/web", repos: ["a/web"], state: .running(try running()), canReload: true, outcome: .refused("repos.0.name: bad"), failure: nil)
    #expect(refused.problem == "Saved, but Carrier kept its settings: repos.0.name: bad")
    let failed = projectWatchRow(repo: "a/web", repos: [], state: .running(try running()), canReload: true, outcome: nil, failure: "other/web has the same folder name as a/web; Solve's worktree paths have no owner")
    #expect(failed.problem?.hasPrefix("other/web has the same folder name") == true)
    let invalid = projectWatchRow(repo: "c/web", repos: ["a/web", "b/web"], state: .running(try running()), canReload: true, outcome: nil, failure: nil)
    #expect(invalid.problem == "b/web has the same folder name as a/web; Solve's worktree paths have no owner")
    let unreadable = projectWatchRow(repo: "a/web", repos: nil, state: .stopped, canReload: false, outcome: nil, failure: nil)
    #expect(unreadable.canChange == false && unreadable.problem?.hasPrefix("The engine is not configured") == true)
}
