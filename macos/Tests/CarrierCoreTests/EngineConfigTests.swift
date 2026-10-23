import Foundation
import Testing
@testable import CarrierCore

private func object(_ data: Data?) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any] ?? [:]
}

private let file = Data(#"{"root":"~/work","repos":[{"name":"a/b"}],"limits":{"maxReviews":7}}"#.utf8)

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
    #expect(Set(config.problems.keys) == ["pollIntervalMinutes", "logLevel", "maxConcurrentEpics", "maxReviews", "maxExecutionRetries", "maxExecutionHours", "githubCallTimeoutSeconds"])
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
    #expect(written["root"] as? String == "~/work" && (written["repos"] as? [Any])?.count == 1)
    #expect(written["pollIntervalMinutes"] == nil && written["logLevel"] == nil)
    let limits = try #require(written["limits"] as? [String: Any])
    #expect(limits["maxConcurrentEpics"] as? Int == 6 && limits["maxExecutionHours"] as? String == "unlimited" && limits["maxReviews"] == nil)
    #expect(EngineConfig(json: try #require(config.applied(to: file))) == config)
}

@Test func theLimitsObjectGoesWhenNothingIsLeftInIt() {
    let written = object(EngineConfig().applied(to: file))
    #expect(written["limits"] == nil && written["root"] as? String == "~/work")
}

@Test func theAppNeverMakesAConfigFileNorWritesBadValues() {
    #expect(EngineConfig().applied(to: Data()) == nil)
    #expect(EngineConfig().applied(to: Data("[]".utf8)) == nil)
    var config = EngineConfig()
    config.maxReviews = 0
    #expect(config.applied(to: file) == nil)
}
