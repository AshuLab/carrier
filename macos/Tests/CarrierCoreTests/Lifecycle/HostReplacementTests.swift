import Foundation
import Testing
@testable import CarrierCore

@Test func anOlderHostIsReplacedWhenNoSessionIsWorking() {
    #expect(hostReplacement(running: "0.1.0", installed: "0.2.0", working: false) == .replace)
    #expect(hostReplacement(running: "0.9.0", installed: "0.10.0", working: false) == .replace)
    #expect(hostReplacement(running: "1.2", installed: "1.2.1", working: false) == .replace)
}

@Test func anOlderHostWithASessionWorkingAsksForARestart() {
    #expect(hostReplacement(running: "0.1.0", installed: "0.2.0", working: true) == .askRestart)
}

@Test func anEqualOrNewerHostStays() {
    #expect(hostReplacement(running: "0.2.0", installed: "0.2.0", working: false) == .keep)
    #expect(hostReplacement(running: "1.2", installed: "1.2.0", working: false) == .keep)
    #expect(hostReplacement(running: "0.3.0", installed: "0.2.0", working: false) == .keep)
    #expect(hostReplacement(running: "0.3.0", installed: "0.2.0", working: true) == .keep)
}

@Test func aVersionThatIsNotNumbersSeparatedByDotsStays() {
    for bad in ["", "unknown", "1.2-beta", "1..2", ".1", "1.", "v1.2", "1.٣"] {
        #expect(hostReplacement(running: bad, installed: "9.0.0", working: false) == .keep)
        #expect(hostReplacement(running: "0.1.0", installed: bad, working: false) == .keep)
        #expect(hostReplacement(running: "0.1.0", installed: bad, working: true) == .keep)
    }
}

@Test func theLineCarrierPrintsReadsAsItIs() {
    #expect(versionNumbers("0.1.0\n") == [0, 1, 0])
    #expect(versionNumbers("usage: carrier") == nil)
}

@Test func anOlderEngineWaitsWhileItWorksAndIsReplacedWhenItDoesNot() {
    #expect(engineReplacement(running: "0.1.0", installed: "0.2.0", executionsInFlight: 2) == .pauseAndWait)
    #expect(engineReplacement(running: "0.1.0", installed: "0.2.0", executionsInFlight: 0) == .replace)
    #expect(engineReplacement(running: "0.9.0", installed: "0.10.0", executionsInFlight: 0) == .replace)
}

@Test func anEqualNewerOrUnreadableEngineStays() {
    #expect(engineReplacement(running: "0.2.0", installed: "0.2.0", executionsInFlight: 0) == .keep)
    #expect(engineReplacement(running: "0.3.0", installed: "0.2.0", executionsInFlight: 1) == .keep)
    for bad in ["", "unknown", "1.2-beta"] {
        #expect(engineReplacement(running: bad, installed: "9.0.0", executionsInFlight: 0) == .keep)
        #expect(engineReplacement(running: "0.1.0", installed: bad, executionsInFlight: 3) == .keep)
    }
}

// MARK: what lets `carrier --version` be remembered

private func scratchFolder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stamp-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
}

@Test func theSameFileHasTheSameStampAndAnotherSizeChangesIt() throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("carrier")
    try Data("one".utf8).write(to: file)
    let first = programStamp([file.path])
    #expect(first != nil && programStamp([file.path]) == first)
    try Data("longer".utf8).write(to: file)
    #expect(programStamp([file.path]) != first)
}

@Test func aLinkPointedAtAnotherFileChangesTheStamp() throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let old = folder.appendingPathComponent("0.1.0"), new = folder.appendingPathComponent("0.2.0"), link = folder.appendingPathComponent("carrier")
    try Data("same".utf8).write(to: old)
    try Data("same".utf8).write(to: new)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: old)
    let before = programStamp([link.path])
    try FileManager.default.removeItem(at: link)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: new)
    #expect(before != nil && programStamp([link.path]) != before)
}

@Test func aPathThatDoesNotExistHasNoStamp() throws {
    let folder = try scratchFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("carrier")
    try Data("x".utf8).write(to: file)
    #expect(programStamp([file.path, folder.appendingPathComponent("missing").path]) == nil)
    #expect(programStamp([]) == nil)
}

private func scratchDefaults() -> (UserDefaults, () -> Void) {
    let name = "remembered-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (defaults, { defaults.removePersistentDomain(forName: name) })
}

@Test func theVersionIsReadOnceWhileTheStampIsTheSameAndAgainWhenItChanges() async {
    let (defaults, clean) = scratchDefaults()
    defer { clean() }
    var stamp = "a", runs = 0
    func ask() async -> String? { await rememberedVersion(stamp: { stamp }, defaults: defaults) { runs += 1; return stamp == "a" ? "0.1.0" : "0.2.0" } }
    let (a, b) = (await ask(), await ask())
    #expect(a == "0.1.0" && b == "0.1.0" && runs == 1)
    stamp = "b" // the Homebrew file is another one
    let (c, d) = (await ask(), await ask())
    #expect(c == "0.2.0" && d == "0.2.0" && runs == 2)
}

@Test func aRunThatFailedOrHasNoStampKeepsNothing() async {
    let (defaults, clean) = scratchDefaults()
    defer { clean() }
    var runs = 0
    #expect(await rememberedVersion(stamp: { "a" }, defaults: defaults) { runs += 1; return nil } == nil)
    #expect(await rememberedVersion(stamp: { "a" }, defaults: defaults) { runs += 1; return "0.1.0" } == "0.1.0") // the failure was not kept: it runs again
    #expect(await rememberedVersion(stamp: { nil }, defaults: defaults) { runs += 1; return "9.9.9" } == "9.9.9" && runs == 3)
    #expect(await rememberedVersion(stamp: { "a" }, defaults: defaults) { runs += 1; return "x" } == "0.1.0" && runs == 3) // what no stamp ran left the kept one alone
}

@Test func aStampThatChangedWhileItRanKeepsNothing() async {
    let (defaults, clean) = scratchDefaults()
    defer { clean() }
    var calls = 0
    // the first stamp is "a" and the second "b": the file was swapped under the run
    let first = await rememberedVersion(stamp: { calls += 1; return calls == 1 ? "a" : "b" }, defaults: defaults) { "0.2.0" }
    #expect(first == "0.2.0" && defaults.dictionary(forKey: "carrier.installedVersion") == nil)
}
