import Foundation
import Testing

@Test func theTestPathsAreTheSameFromAFileTwoFoldersDeeperThanAnyTest() {
    let here = testPaths()
    let tests = here.fixtures.deletingLastPathComponent()
    let deeper = tests.appendingPathComponent("CarrierCoreTests/Area/Part/Probe.swift").path
    #expect(testPaths(from: deeper) == here)
    #expect(FileManager.default.fileExists(atPath: here.fixtures.appendingPathComponent("snapshot.json").path))
    #expect(FileManager.default.fileExists(atPath: here.sources.appendingPathComponent("CarrierCore").path))
    #expect(FileManager.default.fileExists(atPath: here.root.appendingPathComponent("macos/Package.swift").path))
}
