import Foundation
import Testing
@testable import CarrierCore

// What the Behavior and Repos tabs save with (`saveConfig`): the file read again, rewritten, written, and then the engine asked to reload.

private func temporaryConfig(_ text: String = #"{"keep":1,"repos":[{"name":"a/b"}]}"#) throws -> String {
    let path = NSTemporaryDirectory() + "carrier-config-save-\(UUID().uuidString).json"
    try text.write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

@Test func theBehaviorTabsValuesAreWrittenAndThenTheEngineIsAskedToReload() throws {
    let path = try temporaryConfig(#"{"keep":1,"pollIntervalMinutes":5}"#)
    let engine = FakeReload(file: path)
    var draft = EngineConfig()
    draft.pollIntervalMinutes = 2
    let result = saveConfig(path: path, unusable: "unusable", edit: { draft.applied(to: $0) }, reload: engine.reload)
    #expect(result == .saved && engine.calls == 1)
    let written = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
    #expect(written["pollIntervalMinutes"] as? Double == 2 && written["keep"] as? Int == 1)
    #expect(engine.seen[0] == engine.now)
}

@Test func theReposTabsListIsWrittenAndThenTheEngineIsAskedToReload() throws {
    let path = try temporaryConfig()
    let engine = FakeReload(file: path)
    #expect(saveConfig(path: path, unusable: "unusable", edit: { applyingRepos(["a/b", "c/d"], to: $0) }, reload: engine.reload) == .saved)
    #expect(engine.calls == 1 && configRepoNames(json: engine.seen[0] ?? Data()) == ["a/b", "c/d"])
}

@Test func aFileThatCannotBeReadOrRewrittenOrWrittenAsksNothing() throws {
    let path = try temporaryConfig()
    let engine = FakeReload(file: path)
    #expect(saveConfig(path: path, unusable: "unusable", edit: { _ in nil }, reload: engine.reload) == .failed("unusable"))
    #expect(saveConfig(path: path + ".missing", unusable: "unusable", edit: { $0 }, reload: engine.reload) == .failed("unusable"))
    // a folder nobody can write to: the replacement cannot be made
    let folder = NSTemporaryDirectory() + "carrier-config-save-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: URL(fileURLWithPath: folder + "/config.json"))
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder)
        try? FileManager.default.removeItem(atPath: folder)
    }
    guard case .failed = saveConfig(path: folder + "/config.json", unusable: "unusable", edit: { $0 }, reload: engine.reload) else {
        Issue.record("expected the write to fail")
        return
    }
    #expect(engine.calls == 0)
}

@Test func aSaveTheEngineRefusedToApplyIsWritten() throws {
    let path = try temporaryConfig()
    let engine = FakeReload(file: path, problem: "pollIntervalMinutes: must be positive")
    let result = saveConfig(path: path, unusable: "unusable", edit: { applyingRepos(["a/b", "c/d"], to: $0) }, reload: engine.reload)
    #expect(result == .saved)
    #expect(configRepoNames(json: try Data(contentsOf: URL(fileURLWithPath: path))) == ["a/b", "c/d"])
}
