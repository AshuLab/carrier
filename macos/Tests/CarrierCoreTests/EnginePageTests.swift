import Testing
@testable import CarrierCore

@Test func startingHoldsTheTwoSwitchesAboutStartingAndStoppingCarrier() {
    let groups = engineGroups(configured: true, folder: "/h/.carrier", home: "/h", exists: { _ in true })
    #expect(groups.map(\.title) == ["Starting", "Files"])
    #expect(groups[0].rows == [
        EngineRow(id: .startOnOpen, title: "Start Carrier when the app opens", detail: "Carrier starts working on ready epics as soon as the app opens"),
        EngineRow(id: .confirmStop, title: "Ask before stopping Carrier", detail: "Only when stopping would interrupt epics that are running"),
    ])
}

@Test func withoutAConfigTheStartRowSaysItDoesNothingYetAndTheOtherIsTheSame() {
    let rows = engineGroups(configured: false, folder: "/h/.carrier", home: "/h", exists: { _ in true })[0].rows
    #expect(rows[0].detail == "Does nothing until the engine is configured")
    #expect(rows[1] == engineGroups(configured: true, folder: "/h/.carrier", home: "/h", exists: { _ in true })[0].rows[1])
}

private func files(exists: @escaping (String) -> Bool, folder: String = "/h/.carrier") -> [EngineRow] {
    engineGroups(configured: true, folder: folder, home: "/h", exists: exists)[1].rows
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
