import Foundation
import Testing
@testable import CarrierCore

private let home = "/Users/ana"
private let ready = SetupSettings(
    carrier: "/Users/ana/.nvm/bin/carrier", node: "/Users/ana/.nvm/bin/node", path: "/usr/bin:/bin"
)

private func model(_ settings: SetupSettings, detecting: Bool = false) -> EngineTabModel {
    engineTab(settings, detecting: detecting, home: home)
}

@Test func everythingFoundIsAGreenBannerAndThreeFoundRows() {
    let tab = model(ready)
    #expect(tab.banner.state == .ready)
    #expect(tab.banner.title == "Start Carrier is ready")
    #expect(tab.rows.map(\.title) == ["Carrier", "Node", "PATH"])
    #expect(tab.rows.allSatisfy { $0.found })
}

@Test func pathsShowTheHomeFolderAsATildeAndTheEnginePathIsCounted() {
    let rows = model(ready).rows
    #expect(rows[0].value == "~/.nvm/bin/carrier")
    #expect(rows[0].revealPath == "/Users/ana/.nvm/bin/carrier")
    // node's folder is put first: /Users/ana/.nvm/bin + /usr/bin + /bin
    #expect(rows[2].value == "3 folders · node’s folder first")
    #expect(rows[2].revealPath == nil)
}

@Test(arguments: [
    (EngineField.carrier, "Start Carrier needs carrier"),
    (.node, "Start Carrier needs node"),
])
func eachMissingValueIsNamedInTheBannerAndItsRowIsNotFound(field: EngineField, title: String) {
    var settings = ready
    settings[field] = ""
    let tab = model(settings)
    #expect(tab.banner.state == .missing)
    #expect(tab.banner.title == title)
    let row = tab.rows.first { $0.field == field }
    #expect(row?.found == false)
    #expect(row?.revealPath == nil)
    #expect(tab.rows.filter { $0.found == false }.count == 1)
}

@Test func aMissingPathIsNotFoundButDoesNotBlockStart() {
    var settings = ready
    settings.path = ""
    let tab = model(settings)
    #expect(tab.rows.last?.found == false)
    #expect(tab.banner.state == .ready)
}

@Test func severalMissingValuesAreAllNamed() {
    var settings = ready
    settings.node = ""
    settings.carrier = ""
    #expect(model(settings).banner.title == "Start Carrier needs node and carrier")
    #expect(model(SetupSettings()).rows.allSatisfy { $0.found == false })
}

@Test func whileDetectingTheBannerSaysSoWhateverIsMissing() {
    #expect(model(ready, detecting: true).banner.state == .detecting)
    #expect(model(SetupSettings(), detecting: true).banner.state == .detecting)
}

@Test func theFieldsAreChosenAsFilesAndFolders() {
    let choices = model(ready).rows.map(\.choice)
    #expect(choices == [.file, .file, .edit])
}

@Test func thePathsStayClosedWhenAllIsFoundUntilAskedAndOpenThemselvesOtherwise() {
    let readyBanner = model(ready).banner
    #expect(enginePathsShown(readyBanner, opened: false) == false)
    #expect(enginePathsShown(readyBanner, opened: true))
    var missing = ready
    missing.carrier = ""
    #expect(enginePathsShown(model(missing).banner, opened: false))
    #expect(enginePathsShown(model(ready, detecting: true).banner, opened: false))
}
