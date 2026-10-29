import Foundation
import Testing
@testable import CarrierCore

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

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

@Test func theWholeListNeedsOneRepoAndNoProblems() {
    #expect(reposProblem([]) == "The config needs at least one repo.")
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
    #expect(applyingRepos([], to: file) == nil)
    #expect(applyingRepos(["acme/web", "other/web"], to: file) == nil)
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
    #expect(removalText(some) == "It has epics (2 queued, 1 needs you). They stop where they are, untouched, and continue if you add the repo again. Nothing is deleted. It takes effect when you save; Revert puts it back.")
    #expect(removalText(RepoEpics()) == "It has no epics. You can add it again whenever you want. It takes effect when you save; Revert puts it back.")
    #expect(removalText(nil).hasPrefix("Its epics, if it has any, stop where they are"))
}

@Test func theRowsSayHowEachRepoIs() throws {
    var snapshot = try running()
    let name = try #require(snapshot.watched?.first?.repo)
    snapshot.watched = [PanelSnapshot.Watched(repo: name, lastCheckedAt: snapshot.now - 120_000, ok: true, error: nil, agents: snapshot.watched!.first!.agents),
                        PanelSnapshot.Watched(repo: "bad/repo", lastCheckedAt: snapshot.now, ok: false, error: "GitHub refused the profile", agents: snapshot.watched!.first!.agents)]
    let rows = repoRows(draft: [name, "bad/repo", "later/one", "new/repo"], saved: [name, "bad/repo", "later/one"], snapshot: snapshot)
    #expect(rows[0].health == .ok && rows[0].line.hasPrefix("Checked 2m"))
    #expect(rows[1].health == .error && rows[1].line == "GitHub refused the profile")
    #expect(rows[2].health == .unknown && rows[2].line.hasPrefix("Carrier has not loaded it yet"))
    #expect(rows[3].isNew && rows[3].line.hasPrefix("Not checked yet"))

    let stopped = repoRows(draft: ["a/b"], saved: ["a/b"], snapshot: nil)
    #expect(stopped == [RepoRow(name: "a/b", health: .unknown, line: "Carrier is stopped", epics: nil, isNew: false)])
    #expect(stopped[0].owner == "a" && stopped[0].repo == "b" && stopped[0].gitHubURL?.absoluteString == "https://github.com/a/b")
    #expect(stopped[0].clonePath(engine: "/data/carrier/engine") == "/data/carrier/engine/repos/a/b")
    #expect(tildePath("/Users/ana/.carrier/engine/repos/a/b", home: "/Users/ana") == "~/.carrier/engine/repos/a/b" && tildePath("/srv/x", home: "/Users/ana") == "/srv/x")
}
