import Testing
@testable import CarrierCore

@Test func startingHoldsTheTwoSwitchesAboutStartingAndStoppingCarrier() {
    let groups = engineGroups(configured: true)
    #expect(groups.map(\.title) == ["Starting"])
    #expect(groups[0].rows == [
        EngineRow(id: .startOnOpen, title: "Start Carrier when the app opens", detail: "Carrier starts working on ready epics as soon as the app opens"),
        EngineRow(id: .confirmStop, title: "Ask before stopping Carrier", detail: "Only when stopping would interrupt epics that are running"),
    ])
}

@Test func withoutAConfigTheStartRowSaysItDoesNothingYetAndTheOtherIsTheSame() {
    let rows = engineGroups(configured: false)[0].rows
    #expect(rows[0].detail == "Does nothing until the engine is configured")
    #expect(rows[1] == engineGroups(configured: true)[0].rows[1])
}
