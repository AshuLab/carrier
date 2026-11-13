import Foundation
import Testing
@testable import CarrierCore

@Test func startingHoldsTheTwoSwitchesAboutStartingAndStoppingCarrier() {
    let groups = engineGroups(configured: true, identity: nil)
    #expect(groups.map(\.title) == ["Starting", "GitHub identity"])
    #expect(groups[0].rows == [
        EngineRow(id: .startOnOpen, title: "Start Carrier when the app opens", detail: "Carrier starts working on ready epics as soon as the app opens"),
        EngineRow(id: .confirmStop, title: "Ask before stopping Carrier", detail: "Only when stopping would interrupt epics that are running"),
    ])
}

@Test func withoutAConfigTheStartRowSaysItDoesNothingYetAndTheOtherIsTheSame() {
    let rows = engineGroups(configured: false, identity: nil)[0].rows
    #expect(rows[0].detail == "Does nothing until the engine is configured")
    #expect(rows[1] == engineGroups(configured: true, identity: nil)[0].rows[1])
}

private func identityRow(_ json: String) -> EngineRow {
    engineGroups(configured: true, identity: EngineIdentity(config: Data(json.utf8)))[1].rows[0]
}

@Test func theIdentityRowListsTheDeclaredProfilesAndHasNoProblem() throws {
    let json = #"{"profiles":{"zed":{},"bot":{}},"orchestratorProfile":"bot"}"#
    let row = identityRow(json)
    #expect(row.id == .orchestratorProfile && row.title == "Carrier acts on GitHub as")
    #expect(row.detail == "Reads issues and PRs and changes labels. Default is the author's identity" && row.problem == nil)
    #expect(try #require(EngineIdentity(config: Data(json.utf8))).choices == ["bot", "zed"])
}

@Test func withoutADeclaredProfileTheChoiceIsTheDefaultAlone() throws {
    #expect(identityRow("{}").problem == nil)
    #expect(try #require(EngineIdentity(config: Data("{}".utf8))).choices.isEmpty)
}

@Test func aProfileTheFileNamesButDoesNotDeclareIsKeptOnTheListAndShownAsAProblem() throws {
    let json = #"{"profiles":{"bot":{}},"orchestratorProfile":"gone"}"#
    #expect(identityRow(json).problem == "“gone” is not in profiles; it is kept until you pick another")
    #expect(try #require(EngineIdentity(config: Data(json.utf8))).choices == ["bot", "gone"])
}

@Test func aFileThatCannotBeReadHasNoIdentityAndTheRowSaysWhy() {
    #expect(EngineIdentity(config: Data("[]".utf8)) == nil && EngineIdentity(config: Data()) == nil)
    #expect(engineGroups(configured: false, identity: nil)[1].rows[0].detail == "Available once the engine is configured")
}
