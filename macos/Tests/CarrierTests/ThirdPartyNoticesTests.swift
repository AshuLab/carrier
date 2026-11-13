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

/// FluidAudio is linked with `text-processing-rs` and fastcluster, which ask for their notices in a binary distribution, and the app carries the
/// licence texts of what it links: the file names them, and `build-app.sh` and `check-app.sh` put the texts in the bundle.
@Test func theNoticesNameWhatFluidAudioCarriesAndTheLicencesTheAppShips() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let notices = try String(contentsOf: root.appending(path: "THIRD-PARTY-NOTICES.md"), encoding: .utf8)
    #expect(["text-processing-rs", "fastcluster", "swift-transformers", "Apache License 2.0", "Contents/Resources/Licenses"].filter { notices.contains($0) == false } == [])
    let build = try String(contentsOf: root.appending(path: "macos/build-app.sh"), encoding: .utf8)
    let check = try String(contentsOf: root.appending(path: "macos/scripts/check-app.sh"), encoding: .utf8)
    for file in ["FluidAudio/LICENSE", "ThirdPartyLicenses", "argmax-oss-swift/LICENSE", "NOTICES", "THIRD-PARTY-NOTICES.md"] {
        #expect(build.contains(file), "build-app.sh does not copy \(file)")
        #expect(check.contains(file), "check-app.sh does not check \(file)")
    }
}
