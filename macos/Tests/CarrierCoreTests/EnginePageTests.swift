import Foundation
import Testing
@testable import CarrierCore

@Test func startingHoldsTheTwoSwitchesAboutStartingAndStoppingCarrier() {
    let groups = page(configured: true)
    #expect(groups.map(\.title) == ["Starting", "Programs", "GitHub identity", "Files"])
    #expect(groups[0].rows == [
        EngineRow(id: .startOnOpen, title: "Start Carrier when the app opens", detail: "Carrier starts working on ready epics as soon as the app opens"),
        EngineRow(id: .confirmStop, title: "Ask before stopping Carrier", detail: "Only when stopping would interrupt epics that are running"),
    ])
}

@Test func withoutAConfigTheStartRowSaysItDoesNothingYetAndTheOtherIsTheSame() {
    let rows = page(configured: false)[0].rows
    #expect(rows[0].detail == "Does nothing until the engine is configured")
    #expect(rows[1] == page(configured: true)[0].rows[1])
}

/// The page as the view asks for it; the path of every Files row exists unless `exists` says otherwise.
private func page(
    configured: Bool, programs: EnginePrograms = programs(), identity: EngineIdentity? = nil, folder: String = "/h/.carrier",
    exists: @escaping (String) -> Bool = { _ in true }
) -> [EngineGroup] {
    engineGroups(configured: configured, programs: programs, identity: identity, folder: folder, home: "/h", exists: exists)
}

private func identityRow(_ json: String) -> EngineRow {
    page(configured: true, identity: EngineIdentity(config: Data(json.utf8)))[2].rows[0]
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
    #expect(page(configured: false)[2].rows[0].detail == "Available once the engine is configured")
}

private func files(exists: @escaping (String) -> Bool, folder: String = "/h/.carrier") -> [EngineRow] {
    page(configured: true, folder: folder, exists: exists)[3].rows
}

@Test func filesShowThreeRowsWithTheirPathsInThePersonsWordsAndTheButtonEachOneHas() {
    let rows = files(exists: { _ in true })
    #expect(rows.map(\.title) == ["Carrier folder", "Logs", "Start log"])
    #expect(rows[2].detail == "What the app saw the last time it started Carrier")
    #expect(rows.map { $0.file?.shown } == ["~/.carrier", "~/.carrier/engine/logs", "~/.carrier/engine/logs/app-start.log"])
    #expect(rows.map { $0.file?.path } == ["/h/.carrier", "/h/.carrier/engine/logs", "/h/.carrier/engine/logs/app-start.log"])
    #expect(rows.map { $0.file?.buttonTitle } == ["Reveal", "Reveal", "Open"])
    #expect(rows.allSatisfy { $0.file?.exists == true })
}

@Test func aFileThatDoesNotExistYetHasItsButtonDisabledAndSaysSo() {
    let rows = files(exists: { $0 == "/h/.carrier" })
    #expect(rows.map { $0.file?.exists } == [true, false, false])
    #expect(rows.map { $0.file?.buttonTitle } == ["Reveal", "Not created yet", "Not created yet"])
}

@Test func aCarrierFolderOutsideTheHomeFolderIsShownWhole() {
    #expect(files(exists: { _ in false }, folder: "/data/carrier").map { $0.file?.shown } == ["/data/carrier", "/data/carrier/engine/logs", "/data/carrier/engine/logs/app-start.log"])
}

private func programs(
    carrier: String? = "/opt/homebrew/bin/carrier", own: Bool = false, version: String? = "1.4.2",
    node: String = "/opt/homebrew/bin/node", path: String = "/opt/homebrew/bin:/usr/bin", nodeVersion: String? = "v22.1.0"
) -> EnginePrograms {
    EnginePrograms(carrier: carrier, carrierIsOwn: own, carrierVersion: version, setup: SetupSettings(node: node, path: path), nodeVersion: nodeVersion)
}

private func programRows(_ programs: EnginePrograms) -> [EngineRow] { page(configured: true, programs: programs)[1].rows }

@Test func programsSitAfterStartingAndShowWhatTheAppRunsCarrierWith() {
    let groups = page(configured: true)
    #expect(groups.map(\.title) == ["Starting", "Programs", "GitHub identity", "Files"])
    #expect(groups[1].rows.map(\.id) == [.carrier, .node, .path, .lookAgain])
    let rows = groups[1].rows
    #expect(rows[0].note == "/opt/homebrew/bin/carrier" && rows[0].detail == "Version 1.4.2" && rows[0].offersHomebrew == false)
    #expect(rows[1].note == "/opt/homebrew/bin/node" && rows[1].detail == "Version 22.1.0")
    #expect(rows[2].note == "/opt/homebrew/bin:/usr/bin" && rows[2].detail == "What the engine and the chat host run with")
    #expect(rows[3].title == "Look for the tools again")
    #expect(rows[3].detail == "Asks your shell where node and the PATH are. Use it after installing a tool while the app was open")
}

@Test func aCarrierTheAppDoesNotFindSaysNotFoundInPlaceOfAPath() {
    let row = programRows(programs(carrier: nil, version: nil))[0]
    #expect(row.note == "Not found" && row.detail.isEmpty && row.offersHomebrew == false)
}

@Test func aScriptTheyChoseIsTheirOwnAndOffersTheHomebrewOne() {
    let row = programRows(programs(carrier: "/Users/me/carrier/src/terminal/cli/main.ts", own: true))[0]
    #expect(row.note == "/Users/me/carrier/src/terminal/cli/main.ts")
    #expect(row.detail == "Your own carrier · Version 1.4.2")
    #expect(row.offersHomebrew)
}

@Test func aNodeTheShellDidNotFindSaysNotFound() {
    let row = programRows(programs(node: "", nodeVersion: nil))[1]
    #expect(row.note == "Not found" && row.detail.isEmpty)
}

@Test func withNoPathYetTheRowSaysSoAndShowsTheSystemOneTheEngineStartsFrom() {
    let row = programRows(programs(node: "", path: "", nodeVersion: nil))[2]
    #expect(row.detail == "Not found yet, so the engine and the chat host start from the system's")
    #expect(row.note == "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin")
}
