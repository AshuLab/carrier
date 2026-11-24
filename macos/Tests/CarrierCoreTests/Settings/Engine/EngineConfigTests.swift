import Foundation
import Testing
@testable import CarrierCore

private func object(_ data: Data?) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data ?? Data())) as? [String: Any] ?? [:]
}

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
    }
    for days in [1, 30] {
        config.finishedWindowDays = days
        #expect(config.problems.isEmpty)
    }
}

@Test func theRunTimeTakesUnlimitedOrANumberOfHours() throws {
    #expect(EngineConfig(json: Data(#"{"limits":{"maxExecutionHours":"unlimited"}}"#.utf8)).maxExecutionHours == nil)
    #expect(EngineConfig(json: Data(#"{"limits":{"maxExecutionHours":8}}"#.utf8)).maxExecutionHours == 8)
}

@Test func anUndeclaredOrchestratorProfileStaysOnTheListUntilAnotherIsPicked() throws {
    let file = Data(#"{"profiles":{"bot":{}},"orchestratorProfile":"gone"}"#.utf8)
    let identity = try #require(EngineIdentity(config: file))
    #expect(identity.undeclared == "gone" && identity.choices == ["bot", "gone"] && identity.current == "gone")
}

@Test func theOrchestratorChoiceListsTheDefaultFirstAndAFileThatIsNotAnObjectHasNoIdentity() {
    #expect(EngineIdentity.options(nil).map(\.title) == [EngineIdentity.defaultTitle])
    #expect(EngineIdentity(config: Data("[]".utf8)) == nil)
}
