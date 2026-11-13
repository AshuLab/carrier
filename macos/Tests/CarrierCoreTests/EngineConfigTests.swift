import Foundation
import Testing
@testable import CarrierCore

private func object(_ data: Data?) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any] ?? [:]
}

private let file = Data(#"{"keep":"~/work","repos":[{"name":"a/b"}],"limits":{"maxReviews":7}}"#.utf8)

@Test func aFileWithoutTheValuesReadsAsTheEnginesDefaults() {
    #expect(EngineConfig(json: Data("{}".utf8)) == EngineConfig())
    #expect(EngineConfig(json: Data("not json".utf8)) == EngineConfig())
}

@Test func theValuesInTheFileAreRead() {
    let config = EngineConfig(json: Data(#"{"pollIntervalMinutes":0.5,"logLevel":"debug","limits":{"maxConcurrentEpics":2,"maxExecutionHours":"unlimited"}}"#.utf8))
    #expect(config.pollIntervalMinutes == 0.5 && config.logLevel == "debug" && config.maxConcurrentEpics == 2)
    #expect(config.maxExecutionHours == nil && config.maxReviews == 5)
}

@Test func whatTheEngineWouldRefuseIsNamed() {
    var config = EngineConfig()
    #expect(config.problems.isEmpty)
    config.pollIntervalMinutes = 0
    config.logLevel = "loud"
    config.maxConcurrentEpics = 0
    config.maxReviews = 0
    config.maxExecutionRetries = -1
    config.maxExecutionHours = 0
    config.githubCallTimeoutSeconds = 0
    config.finishedWindowDays = 0
    #expect(Set(config.problems.keys) == ["pollIntervalMinutes", "logLevel", "maxConcurrentEpics", "maxReviews", "maxExecutionRetries", "maxExecutionHours", "githubCallTimeoutSeconds", "finishedWindowDays"])
    config.maxExecutionRetries = 0
    config.maxExecutionHours = nil
    #expect(config.problems["maxExecutionRetries"] == nil && config.problems["maxExecutionHours"] == nil)
}

@Test func applyingKeepsEverythingElseAndWritesOnlyWhatDiffersFromTheDefaults() throws {
    var config = EngineConfig(json: file)
    config.maxConcurrentEpics = 6
    config.maxReviews = 5  // back to the default: leaves the file
    config.maxExecutionHours = nil
    let written = object(config.applied(to: file))
    #expect(written["keep"] as? String == "~/work" && (written["repos"] as? [Any])?.count == 1)
    #expect(written["pollIntervalMinutes"] == nil && written["logLevel"] == nil)
    let limits = try #require(written["limits"] as? [String: Any])
    #expect(limits["maxConcurrentEpics"] as? Int == 6 && limits["maxExecutionHours"] as? String == "unlimited" && limits["maxReviews"] == nil)
    #expect(EngineConfig(json: try #require(config.applied(to: file))) == config)
}

@Test func theLimitsObjectGoesWhenNothingIsLeftInIt() {
    let written = object(EngineConfig().applied(to: file))
    #expect(written["limits"] == nil && written["keep"] as? String == "~/work")
}

@Test func theAppNeverMakesAConfigFileNorWritesBadValues() {
    #expect(EngineConfig().applied(to: Data()) == nil)
    #expect(EngineConfig().applied(to: Data("[]".utf8)) == nil)
    var config = EngineConfig()
    config.maxReviews = 0
    #expect(config.applied(to: file) == nil)
}

@Test func theFinishedWindowDefaultsTo15AndIsReadFromTheFile() {
    #expect(EngineConfig().finishedWindowDays == 15)
    #expect(EngineConfig(json: Data("{}".utf8)).finishedWindowDays == 15)
    #expect(EngineConfig(json: Data(#"{"finishedWindowDays":7}"#.utf8)).finishedWindowDays == 7)
}

@Test func theFinishedWindowTakesWholeDaysFrom1To30() {
    var config = EngineConfig()
    for days in [0, 31, -1] {
        config.finishedWindowDays = days
        #expect(config.problems["finishedWindowDays"] == "Must be a whole number from 1 to 30")
        #expect(config.applied(to: file) == nil)
    }
    for days in [1, 30] {
        config.finishedWindowDays = days
        #expect(config.problems.isEmpty)
    }
}

@Test func theFinishedWindowIsSavedAtTheTopLevelWithoutTouchingTheRest() throws {
    var config = EngineConfig(json: file)
    config.finishedWindowDays = 7
    let written = object(config.applied(to: file))
    #expect(written["finishedWindowDays"] as? Int == 7)
    #expect(written["keep"] as? String == "~/work" && (written["repos"] as? [Any])?.count == 1)
    #expect((written["limits"] as? [String: Any])?["maxReviews"] as? Int == 7)
    #expect(EngineConfig(json: try #require(config.applied(to: file))) == config)
    config.finishedWindowDays = 15  // back to the default: leaves the file
    #expect(object(config.applied(to: file))["finishedWindowDays"] == nil)
}

@Test func theRunTimeTakesUnlimitedOrANumberOfHours() throws {
    #expect(EngineConfig(json: Data(#"{"limits":{"maxExecutionHours":"unlimited"}}"#.utf8)).maxExecutionHours == nil)
    #expect(EngineConfig(json: Data(#"{"limits":{"maxExecutionHours":8}}"#.utf8)).maxExecutionHours == 8)
    var config = EngineConfig()
    config.maxExecutionHours = nil
    #expect((object(config.applied(to: file))["limits"] as? [String: Any])?["maxExecutionHours"] as? String == "unlimited")
    config.maxExecutionHours = 8
    #expect((object(config.applied(to: file))["limits"] as? [String: Any])?["maxExecutionHours"] as? Int == 8)
    #expect(EngineConfig(json: try #require(config.applied(to: file))) == config)
}

@Test func resettingWritesTheDefaultsOfTheEightValuesAndKeepsTheRestOfTheFile() throws {
    let changed = Data(#"{"keep":"~/work","repos":[{"name":"a/b"}],"logLevel":"debug","pollIntervalMinutes":0.5,"finishedWindowDays":3,"limits":{"maxConcurrentEpics":6,"maxReviews":7,"maxExecutionRetries":0,"maxExecutionHours":"unlimited","githubCallTimeoutSeconds":90,"other":1}}"#.utf8)
    let reset = try #require(EngineConfig().applied(to: changed))
    #expect(EngineConfig(json: reset) == EngineConfig())
    let written = object(reset)
    #expect(written["keep"] as? String == "~/work" && (written["repos"] as? [Any])?.count == 1)
    #expect(written["logLevel"] == nil && written["pollIntervalMinutes"] == nil && written["finishedWindowDays"] == nil)
    #expect((written["limits"] as? [String: Any])?.keys.sorted() == ["other"])
}

private let profiled = Data(#"{"zeta":1,"profiles":{"bot":{}},"repos":[{"name":"a/b"}],"orchestratorProfile":"old","limits":{"maxReviews":7}}"#.utf8)

@Test func aProfileIsWrittenAndEveryOtherKeyIsKept() throws {
    let written = object(applyingOrchestratorProfile("bot", to: profiled))
    #expect(written["orchestratorProfile"] as? String == "bot")
    var expected = object(profiled)
    expected["orchestratorProfile"] = "bot"
    #expect(NSDictionary(dictionary: written).isEqual(to: expected))
    #expect(EngineIdentity(config: try #require(applyingOrchestratorProfile("bot", to: profiled)))?.current == "bot")
}

@Test func theDefaultTakesTheKeyOutInsteadOfWritingTheAuthorsName() throws {
    let written = object(applyingOrchestratorProfile(nil, to: profiled))
    #expect(written["orchestratorProfile"] == nil && written.count == object(profiled).count - 1)
    #expect(written["zeta"] as? Int == 1 && (written["repos"] as? [Any])?.count == 1)
}

@Test func anUndeclaredProfileIsKeptUntilAnotherIsPicked() throws {
    let file = Data(#"{"profiles":{"bot":{}},"orchestratorProfile":"gone"}"#.utf8)
    #expect(EngineIdentity(config: file)?.undeclared == "gone")
    #expect(object(applyingOrchestratorProfile("bot", to: file))["orchestratorProfile"] as? String == "bot")
}

/// Like every writer of `config.json`, the identity writes the keys sorted: their values stay, their order does not.
@Test func theIdentityWritesTheKeysSortedLikeEveryWriter() throws {
    let unsorted = Data(#"{"z":2,"orchestratorProfile":"x","a":1}"#.utf8)
    let text = String(decoding: try #require(applyingOrchestratorProfile("y", to: unsorted)), as: UTF8.self)
    #expect(text.contains("\"a\" : 1,\n  \"orchestratorProfile\" : \"y\",\n  \"z\" : 2"))
}

@Test func aFileThatIsNotAnObjectIsRefusedForTheIdentity() {
    #expect(applyingOrchestratorProfile("bot", to: Data("[]".utf8)) == nil)
    #expect(applyingOrchestratorProfile(nil, to: Data("not json".utf8)) == nil)
    #expect(applyingOrchestratorProfile("bot", to: Data()) == nil)
}

@Test func aChosenProfileIsWrittenAndThenTheEngineIsAskedToReload() throws {
    let path = NSTemporaryDirectory() + "carrier-identity-\(UUID().uuidString).json"
    try profiled.write(to: URL(fileURLWithPath: path))
    let engine = FakeReload(file: path)
    #expect(saveOrchestratorProfile("bot", path: path, reload: engine.reload) == .saved)
    #expect(engine.calls == 1 && EngineIdentity(config: engine.seen[0] ?? Data())?.current == "bot")
    #expect(saveOrchestratorProfile(nil, path: path, reload: engine.reload) == .saved)
    #expect(engine.calls == 2 && EngineIdentity(config: engine.seen[1] ?? Data())?.current == nil)
}

@Test func aProfileThatCouldNotBeWrittenAsksTheEngineNothing() throws {
    let path = NSTemporaryDirectory() + "carrier-identity-\(UUID().uuidString).json"
    let engine = FakeReload(file: path)
    #expect(saveOrchestratorProfile("bot", path: path, reload: engine.reload) == .failed("The config file could not be read."))
    try Data("[]".utf8).write(to: URL(fileURLWithPath: path))
    #expect(saveOrchestratorProfile("bot", path: path, reload: engine.reload) == .failed("The config file could not be read."))
    #expect(engine.calls == 0)
    #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data("[]".utf8))
    let folder = NSTemporaryDirectory() + "carrier-identity-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    try profiled.write(to: URL(fileURLWithPath: folder + "/config.json"))
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder)
        try? FileManager.default.removeItem(atPath: folder)
    }
    guard case .failed = saveOrchestratorProfile("bot", path: folder + "/config.json", reload: engine.reload) else {
        Issue.record("expected the write to fail")
        return
    }
    #expect(engine.calls == 0)
}
