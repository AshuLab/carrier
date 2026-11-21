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
