import Foundation
import Testing
@testable import CarrierCore

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures").path

private let reply = #"{"repos":[{"name":"acme/web","private":true,"pushedAt":"2026-10-22T10:00:00Z"},{"name":"not a repo","private":false,"pushedAt":null},{"name":"vemec/encaja","private":false,"pushedAt":null}]}"#

@Test func anEngineWithOnlyAvailableReposIsAskedOnceWithoutPageAndHasNoMore() {
    let engine = FixtureEngine(capabilities: ["availableRepos"], replies: ["availableRepos": reply.replacingOccurrences(of: "]}", with: "],\"hasMore\":true}")])
    defer { engine.stop() }
    #expect(loadAvailableRepos(socketPath: engine.path) == .repos([
        AvailableRepo(name: "acme/web", isPrivate: true, pushedAt: "2026-10-22T10:00:00Z"), AvailableRepo(name: "vemec/encaja"),
    ], hasMore: false))
    #expect(engine.commands == ["availableRepos"] && engine.requests[0]["page"] == nil)
    // nothing was said that could be asked for: no page 2 without the capability
    #expect(loadAvailableRepos(socketPath: engine.path, page: 2) == .unsupported)
    #expect(engine.commands == ["availableRepos"])
}

@Test func noSocketMeansStoppedAnEngineWithoutTheRequestMeansUnsupportedAnErrorMeansGitHub() {
    #expect(loadAvailableRepos(socketPath: "/tmp/carrier-no-such-socket") == .stopped)
    let old = FixtureEngine(capabilities: ["sessions"])
    defer { old.stop() }
    #expect(loadAvailableRepos(socketPath: old.path) == .unsupported)
    #expect(old.commands.isEmpty)
    let failing = FixtureEngine(capabilities: ["availableRepos"], fail: ["availableRepos"])
    defer { failing.stop() }
    #expect(loadAvailableRepos(socketPath: failing.path) == .githubError)
}

@Test func theFixtureServerAnswersTheListOverARealSocket() throws {
    let server = try FixtureServer(fixtures: fixtures)
    defer { server.stop() }
    guard case .repos(let repos, false) = loadAvailableRepos(socketPath: server.socketPath) else { Issue.record("no list"); return }
    #expect(repos.count == 7 && repos.contains(AvailableRepo(name: "vemec/dotfiles")))
}

@Test func eachFailureHasItsOwnMessageAndAListHasNone() {
    #expect(availableReposMessage(.repos([], hasMore: false)) == nil)
    #expect(availableReposMessage(.stopped)?.detail == "Start Carrier to see your repos.")
    #expect(availableReposMessage(.githubError)?.title == "GitHub did not answer")
    #expect(availableReposMessage(.unsupported)?.title == "This Carrier cannot list repos")
}

private func page(_ names: [String], hasMore: Bool) -> String {
    #"{"repos":[\#(names.map { #"{"name":"\#($0)","private":false,"pushedAt":null}"# }.joined(separator: ","))],"hasMore":\#(hasMore)}"#
}

/// Reads page after page the way the picker does: the next one to ask for comes from the list.
private func loadPages(_ engine: FixtureEngine, count: Int) -> AvailableReposList {
    var list = AvailableReposList()
    for _ in 0..<count { list.apply(loadAvailableRepos(socketPath: engine.path, page: list.nextPage)) }
    return list
}

@Test func eachAskForMoreRequestsTheNextPageAndTheReposAreAppendedInOrder() {
    let engine = FixtureEngine(capabilities: ["availableRepos", "availableReposPaged"], pages: [
        1: page(["a/one", "a/two"], hasMore: true), 2: page(["b/three"], hasMore: true), 3: page(["c/four"], hasMore: false),
    ])
    defer { engine.stop() }
    let list = loadPages(engine, count: 3)
    #expect(list.repos.map(\.name) == ["a/one", "a/two", "b/three", "c/four"])
    #expect(engine.requests.map { $0["page"] as? Int } == [1, 2, 3])
    #expect(list.hasMore == false && list.problem == nil)
}

@Test func aPageThatAddsNothingLeavesTheButtonInPlace() {
    let engine = FixtureEngine(capabilities: ["availableRepos", "availableReposPaged"], pages: [
        1: page(["a/one"], hasMore: true), 2: page([], hasMore: true),
    ])
    defer { engine.stop() }
    let list = loadPages(engine, count: 2)
    #expect(list.repos.map(\.name) == ["a/one"] && list.hasMore && list.nextPage == 3)
}

@Test func aPageThatFailsAfterTheFirstKeepsWhatIsLoadedAndTheNextAskRetriesIt() {
    let engine = FixtureEngine(capabilities: ["availableRepos", "availableReposPaged"], pages: [
        1: page(["a/one"], hasMore: true), 2: page(["b/two"], hasMore: false),
    ], failPages: [2])
    defer { engine.stop() }
    let list = loadPages(engine, count: 2)
    #expect(list.repos.map(\.name) == ["a/one"] && list.hasMore && list.blocked == false)
    #expect(list.problem == .githubError && list.nextPage == 2)
}

@Test func aFailingFirstPageShowsTheMessageAlone() {
    let engine = FixtureEngine(capabilities: ["availableRepos", "availableReposPaged"], failPages: [1])
    defer { engine.stop() }
    let list = loadPages(engine, count: 1)
    #expect(list.blocked && list.repos.isEmpty && list.problem == .githubError)
    #expect(list.problem.flatMap(availableReposMessage)?.title == "GitHub did not answer")
}

private let now = ISO8601DateFormatter().date(from: "2026-10-22T12:00:00Z")!
private let available = [
    AvailableRepo(name: "AshuLab/carrier", isPrivate: true, pushedAt: "2026-10-22T11:00:00Z"),
    AvailableRepo(name: "vemec/encaja", pushedAt: "2026-10-19T12:00:00Z"),
    AvailableRepo(name: "AshuLab/docs", pushedAt: "2026-09-02T12:00:00Z"),
    AvailableRepo(name: "acme/web", pushedAt: nil),
    AvailableRepo(name: "other/Web", pushedAt: nil),
]

@Test func theListIsGroupedByOwnerInTheOrderTheEngineSentIt() {
    let groups = repoGroups(available, watched: [], selected: [], query: "", now: now)
    #expect(groups.map(\.owner) == ["AshuLab", "vemec", "acme", "other"])
    #expect(groups[0].choices.map(\.name) == ["AshuLab/carrier", "AshuLab/docs"])
    #expect(groups[0].choices.map(\.detail) == ["pushed 1 h ago", "pushed 7 w ago"])
    #expect(groups[1].choices[0].detail == "pushed 3 d ago" && groups[2].choices[0].detail == "")
}

@Test func aWatchedRepoIsTickedAndOffAndASameNamedFolderIsOffWithItsReason() {
    let groups = repoGroups(available, watched: ["AshuLab/carrier", "acme/web"], selected: [], query: "", now: now)
    let byName = Dictionary(uniqueKeysWithValues: groups.flatMap(\.choices).map { ($0.name, $0) })
    #expect(byName["AshuLab/carrier"]?.watched == true && byName["AshuLab/carrier"]?.detail == "already watched")
    #expect(byName["other/Web"]?.disabled == true && byName["other/Web"]?.detail == "same folder name as acme/web")
    #expect(byName["AshuLab/docs"]?.disabled == false)
}

@Test func twoSelectedReposCannotShareAFolderButTheSelectedOneStaysOn() {
    let groups = repoGroups(available, watched: [], selected: ["acme/web"], query: "", now: now)
    let byName = Dictionary(uniqueKeysWithValues: groups.flatMap(\.choices).map { ($0.name, $0) })
    #expect(byName["acme/web"]?.disabled == false)
    #expect(byName["other/Web"]?.disabled == true && byName["other/Web"]?.detail == "same folder name as acme/web")
}

@Test func theSearchFiltersByNameWhateverTheCase() {
    let names = repoGroups(available, watched: [], selected: [], query: " WEB ", now: now).flatMap(\.choices).map(\.name)
    #expect(names == ["acme/web", "other/Web"])
    #expect(repoGroups(available, watched: [], selected: [], query: "zzz", now: now).isEmpty)
}

@Test func theSecondsSincePushAreSaidInTheLargestUnit() {
    func line(_ iso: String) -> String { pushedLine(iso, now: now) }
    #expect(line("2026-10-22T11:59:30Z") == "pushed just now" && line("2026-10-22T09:00:00Z") == "pushed 3 h ago")
    #expect(line("2026-10-21T10:00:00Z") == "pushed yesterday" && line("2026-10-01T12:00:00Z") == "pushed 3 w ago")
    #expect(line("2026-05-01T12:00:00Z") == "pushed 5 mo ago" && pushedLine(nil, now: now) == "" && pushedLine("yesterday-ish", now: now) == "")
}
