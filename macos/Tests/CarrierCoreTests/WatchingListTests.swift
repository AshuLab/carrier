import Foundation
import Testing

@testable import CarrierCore

private func row(_ name: String, _ health: RepoRow.Health = .ok, epics: RepoEpics? = nil) -> RepoRow {
    RepoRow(name: name, health: health, line: "", epics: epics, isNew: false)
}

private func project(_ name: String, repo: String?, clone: ProjectClone? = nil) -> ProjectRow {
    ProjectRow(path: "/p/\(name)", name: name, repo: repo, clone: clone)
}

@Test func theRepoGitHubRefusedIsFirstAndTheRestAreByName() {
    let rows = [row("acme/web"), row("acme/Api"), row("old/tool", .error), row("acme/lib", .unknown)]
    #expect(watchingOrder(rows).map(\.name) == ["old/tool", "acme/Api", "acme/lib", "acme/web"])
    #expect(watchingOrder([]).isEmpty)
}

@Test func theProjectsToWatchAreThoseCarrierCanTakeFirstAndTheOthersSayWhyTheyAreOff() {
    let projects = [
        project("web", repo: "acme/web"), project("notes", repo: nil), project("Docs", repo: "acme/docs"), project("web-old", repo: "other/web"),
        project("cloning", repo: "acme/new", clone: ProjectClone(repo: "acme/new", folder: "/p/cloning", state: .cloning)), project("lib", repo: "acme/lib"),
    ]
    let choices = watchChoices(projects: projects, watched: ["acme/web"])
    // the watched one and the running clone are not offered; the clash and the folder with no origin are, off
    #expect(choices.map(\.project.name) == ["Docs", "lib", "notes", "web-old"])
    #expect(choices.map(\.canWatch) == [true, true, false, false])
    #expect(choices[2].reason == "No GitHub origin: Carrier watches GitHub repositories")
    #expect(choices[3].reason == "other/web has the same folder name as acme/web; Solve's worktree paths have no owner")
    // a repository is watched whatever the case its origin has
    #expect(watchChoices(projects: [project("web", repo: "Acme/Web")], watched: ["acme/web"]).isEmpty)
}

@Test func aRefusedFailoverStepIsToldInWordsAndSentToAgents() {
    let own = "Invalid config /h/.carrier/engine.json: failover.roles.author.0: failover.roles.author.0: step is the role's own provider and model, so it would move nowhere"
    let banner = refusalBanner(own)
    #expect(banner.title == "Carrier is not using your latest settings")
    #expect(banner.detail == "The Author's failover step 1 is the same provider and model as the Author itself, so it would move nowhere.")
    #expect(banner.raw == own && banner.fix == .agents && banner.fixTitle == "Open Agents")
    #expect(refusalBanner("x: failover.roles.leadReviewer.1: step repeats another step of the list").detail == "The Lead reviewer's failover step 2 repeats another step of its list.")
    #expect(refusalBanner("x: failover.roles.reviewer.0.provider: \"gone\" is not declared in providers").detail == "The Reviewer's failover step 1 uses a provider that is not declared in providers.")
    // a failover reason the page does not know still goes to Agents, with the engine's words only
    #expect(refusalBanner("x: failover.roles.author.0: something new").detail == nil && refusalBanner("x: failover.roles.author.0: something new").fix == .agents)
}

@Test func aRefusalOfAnythingElseIsShownAsTheEngineSaysItWithNoWayToMendIt() {
    let banner = refusalBanner("Invalid config /h/.carrier/engine.json: repos.1.name: must be owner/name")
    #expect(banner.detail == nil && banner.fix == nil && banner.fixTitle == nil && banner.raw.hasSuffix("must be owner/name"))
}
