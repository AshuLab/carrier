import Testing
@testable import CarrierCore

@Test func startingHoldsTheTwoSwitchesAboutStartingAndStoppingCarrier() {
    let groups = engineGroups(configured: true, programs: programs())
    #expect(groups.map(\.title) == ["Starting", "Programs"])
    #expect(groups[0].rows == [
        EngineRow(id: .startOnOpen, title: "Start Carrier when the app opens", detail: "Carrier starts working on ready epics as soon as the app opens"),
        EngineRow(id: .confirmStop, title: "Ask before stopping Carrier", detail: "Only when stopping would interrupt epics that are running"),
    ])
}

@Test func withoutAConfigTheStartRowSaysItDoesNothingYetAndTheOtherIsTheSame() {
    let rows = engineGroups(configured: false, programs: programs())[0].rows
    #expect(rows[0].detail == "Does nothing until the engine is configured")
    #expect(rows[1] == engineGroups(configured: true, programs: programs())[0].rows[1])
}

private func programs(
    carrier: String? = "/opt/homebrew/bin/carrier", own: Bool = false, version: String? = "1.4.2",
    node: String = "/opt/homebrew/bin/node", path: String = "/opt/homebrew/bin:/usr/bin", nodeVersion: String? = "v22.1.0"
) -> EnginePrograms {
    EnginePrograms(carrier: carrier, carrierIsOwn: own, carrierVersion: version, setup: SetupSettings(node: node, path: path), nodeVersion: nodeVersion)
}

private func programRows(_ programs: EnginePrograms) -> [EngineRow] { engineGroups(configured: true, programs: programs)[1].rows }

@Test func programsSitAfterStartingAndShowWhatTheAppRunsCarrierWith() {
    let groups = engineGroups(configured: true, programs: programs())
    #expect(groups.map(\.title) == ["Starting", "Programs"])
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
