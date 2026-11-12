import Foundation
import Testing
@testable import Carrier

/// Apple's recognizer has no download and nothing to name; every other model of the catalog is downloaded by the person and has its notice.
@Test func theNoticesNameEveryModelOfTheCatalog() throws {
    let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "THIRD-PARTY-NOTICES.md")
    let notices = try String(contentsOf: file, encoding: .utf8)
    let models = FluidAudioRecognizer.entries.map(\.model) + WhisperKitRecognizer.entries.map(\.model)
    #expect(models.count == 10)
    #expect(models.filter { notices.contains($0.name) == false }.map(\.name) == [])
}
