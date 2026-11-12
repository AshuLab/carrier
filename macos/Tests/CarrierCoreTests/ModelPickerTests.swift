import Foundation
import Testing
@testable import CarrierCore

// The accounts and models the Agents page's picker lists.

private func reply(_ accounts: [(String, String, String)]) throws -> HostProviders {
    let rows = accounts.map { #"{"name":"\#($0.0)","harness":"\#($0.1)","found":true,"state":"\#($0.2)"}"# }.joined(separator: ",")
    return try JSONDecoder().decode(HostProviders.self, from: Data(#"{"accounts":[\#(rows)],"unadded":[],"servers":[]}"#.utf8))
}

private let icons = ["pro": "claude", "teams": "claude", "codex": "codex", "agy": "antigravity"]

@Test func onlyTheAccountsThatAreReadyAreOfferedAndTheOneARoleNamesStays() throws {
    let host = try reply([("pro", "claude", "ready"), ("teams", "claude", "signedOut"), ("codex", "codex", "ready")])
    #expect(pickerAccounts(host, declared: ["pro", "teams", "codex"], icons: icons, current: []).map(\.name) == ["pro", "codex"])
    let kept = pickerAccounts(host, declared: [], icons: icons, current: ["teams", "gone"])
    #expect(kept.map(\.name) == ["pro", "codex", "teams", "gone"])
    #expect(kept.map(\.ready) == [true, true, false, false])
    #expect(kept[2].harness == "claude" && kept[2].icon == "claude")
}

@Test func withNoAnswerFromTheHostEveryDeclaredAccountIsOfferedWithItsHarnessFromItsIcon() {
    let accounts = pickerAccounts(nil, declared: ["pro", "agy"], icons: icons, current: [])
    #expect(accounts.map(\.name) == ["pro", "agy"] && accounts.allSatisfy(\.ready))
    #expect(accounts.map(\.harness) == ["claude", "agy"])
}

@Test func theModelsOfAnOfferLeaveOutDefaultAndSayMoreOnlyWhenTheyHaveMoreToSay() {
    let offer = AgentOffer(options: [
        ChatOption(id: "model", label: "Model", values: [
            ChatOption.Value(id: "default", label: "Default (recommended)", detail: "Sonnet 5.5", version: nil),
            ChatOption.Value(id: "opus", label: "Opus 5.5", detail: nil, version: "claude-opus-5-5"),
            ChatOption.Value(id: "sonnet", label: "Sonnet", detail: nil, version: "sonnet"),
        ], current: "default"),
    ])
    let models = modelOptions(offer)
    #expect(models.map(\.id) == ["opus", "sonnet"])
    #expect(models.map(\.detail) == ["claude-opus-5-5", nil])
    #expect(modelOptions(nil).isEmpty)
}

@Test func theAgentThatListsAHarnessesModelsIsTheFirstOfItThatWasFound() {
    let agents = [ChatAgent(name: "a", harness: "codex", found: false), ChatAgent(name: "b", harness: "codex", found: true), ChatAgent(name: "c", harness: "claude", found: true)]
    #expect(chatAgent(forHarness: "codex", among: agents) == "b" && chatAgent(forHarness: "claude", among: agents) == "c")
    #expect(chatAgent(forHarness: "agy", among: agents) == nil)
}

@Test func theEffortStepsAreTheEnginesLevelsAfterTheDefault() {
    #expect(effortSteps.map(\.id) == [""] + roleEfforts)
}
