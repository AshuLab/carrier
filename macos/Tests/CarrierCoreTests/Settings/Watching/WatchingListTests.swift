import Foundation
import Testing

@testable import CarrierCore

private func bannerFor(_ reason: Refusal) -> RefusalBanner { refusalBanner(reason, bundle: english.bundle, locale: english.locale) }

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
    let choices = watchChoices(projects: projects, watched: ["acme/web"], bundle: english.bundle, locale: english.locale)
    // the watched one and the running clone are not offered; the clash and the folder with no origin are, off
    #expect(choices.map(\.project.name) == ["Docs", "lib", "notes", "web-old"])
    #expect(choices.map(\.canWatch) == [true, true, false, false])
    #expect(choices[2].reason == "No GitHub origin: Carrier watches GitHub repositories")
    #expect(choices[3].reason == "other/web has the same folder name as acme/web; Solve's worktree paths have no owner")
    // a repository is watched whatever the case its origin has
    #expect(watchChoices(projects: [project("web", repo: "Acme/Web")], watched: ["acme/web"], bundle: english.bundle, locale: english.locale).isEmpty)
}

/// The banner reads the refusal's code and its `path` and `problem`; the words are only what "What Carrier said" shows, so they differ here from the engine's.
private func configProblem(_ path: String, _ problem: String, _ text: String = "any words at all") -> Refusal {
    Refusal(code: "config.problem", params: ["path": .string(path), "problem": .string(problem)], text: text)
}

@Test func aRefusedFailoverStepIsToldByItsParamsAndSentToAgents() {
    let own = configProblem("failover.roles.author.0", "stepOwnRole", "Invalid config /h/.carrier/engine.json: unrelated words")
    let banner = bannerFor(own)
    #expect(banner.title == "Carrier is not using your latest settings")
    #expect(banner.detail == "The Author's failover step 1 is the same provider and model as the Author itself, so it would move nowhere.")
    #expect(banner.raw == "failover.roles.author.0: the step is the role's own provider and model, so it would move nowhere" && banner.fix == .agents && banner.fixTitle == "Open Agents")
    #expect(bannerFor(configProblem("failover.roles.leadReviewer.1", "stepRepeated")).detail == "The Lead reviewer's failover step 2 repeats another step of its list.")
    #expect(bannerFor(configProblem("failover.roles.reviewer.0", "providerNotDeclared")).detail == "The Reviewer's failover step 1 uses a provider that is not declared in providers.")
    // a kind the page does not know still goes to Agents, with the engine's words only
    let unknown = bannerFor(configProblem("failover.roles.author.0", "somethingNew"))
    #expect(unknown.detail == nil && unknown.fix == .agents)
}

@Test func aRefusalOfAnythingElseIsShownAsTheEngineSaysItWithNoWayToMendIt() {
    let notARepo = bannerFor(configProblem("repos[1]", "notARepo", "Invalid config /h/.carrier/engine.json: repos.1.name: must be owner/name"))
    #expect(notARepo.detail == nil && notARepo.fix == nil && notARepo.fixTitle == nil && notARepo.raw.hasSuffix("must be owner/name"))
    let other = bannerFor(Refusal(code: "config.invalid", text: "Invalid config: failover.roles.author.0: something"))
    #expect(other.detail == nil && other.fix == nil)
}

/// A reply with no code (an engine that predates the codes) has its words only: shown as they are, and none of them decides.
@Test func aRefusalWithNoCodeIsShownAsItsWordsAndDecidesNothing() {
    let old = bannerFor(.words("x: failover.roles.author.0: step repeats another step of the list"))
    #expect(old.detail == nil && old.fix == nil && old.raw.hasPrefix("x: failover"))
}
