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

@Test func agyModelsAreTheLinesWithAnIdAndALabelAfterTheFetchingLine() {
    let output = "Fetching available models...\ngemini-4-argon-high\tGemini 4 Argon (High)\nclaude-opus-5-5-low\tClaude Opus 5.5 (Low)\n\n"
    #expect(parseAgyModels(output) == [
        ModelOption(id: "gemini-4-argon-high", label: "Gemini 4 Argon (High)", detail: nil),
        ModelOption(id: "claude-opus-5-5-low", label: "Claude Opus 5.5 (Low)", detail: nil),
    ])
    #expect(parseAgyModels("").isEmpty && parseAgyModels("error: not logged in\n").isEmpty)
}

@Test func antigravityModelsAreListedByFamilyAndTheLevelChoosesTheId() {
    let models = parseAgyModels("""
    Fetching available models...
    gemini-4-argon-high\tGemini 4 Argon (High)
    gemini-4-argon-low\tGemini 4 Argon (Low)
    gemini-4-argon-medium\tGemini 4 Argon (Medium)
    gemini-4-hydrogen-xhigh\tGemini 4 Hydrogen (XHigh)
    gpt-oss-120b-medium\tGPT-OSS 120B (Medium)
    plain\tPlain
    """)
    let families = agyFamilies(models)
    #expect(families.map(\.id) == ["gemini-4-argon", "gemini-4-hydrogen", "gpt-oss-120b", "plain"])
    #expect(families.map(\.label) == ["Gemini 4 Argon", "Gemini 4 Hydrogen", "GPT-OSS 120B", "Plain"])
    #expect(families[0].levels == ["low", "medium", "high"] && families[3].levels.isEmpty)
    #expect(splitAgyID("gemini-4-argon-high") == (family: "gemini-4-argon", level: "high") && splitAgyID("plain").level == nil)
    // the level it had stays when the new family has it; else the middle one; a family with no levels is its own id
    #expect(agyModelID(families[0], keeping: "high") == "gemini-4-argon-high")
    #expect(agyModelID(families[1], keeping: "low") == "gemini-4-hydrogen-xhigh")
    #expect(agyModelID(families[0], keeping: nil) == "gemini-4-argon-medium" && agyModelID(families[3], keeping: "high") == "plain")
}

@Test func theEffortStepsAreTheEnginesLevelsAfterTheDefault() {
    #expect(effortSteps.map(\.id) == [""] + roleEfforts)
}
