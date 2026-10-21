import Foundation
import Testing
@testable import CarrierCore

private func running() throws -> ConnectionState {
    .running(try decodeSnapshot(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/snapshot.json"))))
}

@Test func connectedShowsTheBundleVersionAGreenDotAndTheFooter() throws {
    let sheet = aboutSheet(version: "0.1.0", build: "1", state: try running())
    #expect(sheet.name == "Carrier")
    #expect(sheet.version == "Version 0.1.0 (1)")
    #expect(sheet.connection == "Connected" && sheet.connected)
    #expect(sheet.footer == "© 2026 AshuLab · Signed ad hoc")
}

@Test func stoppedAnIncompatibleVersionAndNoAnswerYetAreGrey() {
    for (state, line) in [(ConnectionState.stopped, "Stopped"), (.incompatible, "Incompatible version"), (nil, "Connecting…")] {
        let sheet = aboutSheet(version: "0.1.0", build: "1", state: state)
        #expect(sheet.connection == line && sheet.connected == false)
    }
}

@Test func theVersionLineSurvivesAMissingBundleKey() {
    #expect(aboutSheet(version: "0.2.0", build: nil, state: .stopped).version == "Version 0.2.0")
    #expect(aboutSheet(version: nil, build: "7", state: .stopped).version == "Build 7")
    #expect(aboutSheet(version: nil, build: nil, state: .stopped).version == "Version unknown")
}

@Test func theThreeLinksAreWebURLs() {
    let links = aboutSheet(version: nil, build: nil, state: .stopped).links
    #expect(links.map(\.title) == ["GitHub", "Documentation", "Release notes"])
    for link in links { #expect(browserURL(link.url.absoluteString) == link.url && link.url.scheme == "https") }
}
