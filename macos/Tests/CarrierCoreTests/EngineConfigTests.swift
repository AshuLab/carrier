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
