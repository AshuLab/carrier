import Foundation
import Testing
@testable import CarrierCore

@Test func theBehaviorPageHasThreeGroupsWithTheirTitlesDescriptionsAndKeys() {
    let listed = behaviorGroups(bundle: english.bundle, locale: english.locale).map { group in
        [group.title] + group.rows.map { "\($0.key) | \($0.title) | \($0.detail)" }
    }
    #expect(listed == [
        ["Pace",
         "pollIntervalMinutes | Look for ready epics every | In minutes",
         "maxConcurrentEpics | Epics at once | Running at the same time"],
        ["When something goes wrong",
         "maxReviews | Review rounds before asking you | A round counts once, however many reviewers it has. Then the epic waits for a person (needs-human)",
         "maxLeadRounds | Lead rounds before asking you | The lead reviewer and the author, one exchange at a time. Then the epic waits for a person (needs-human)",
         "maxExecutionRetries | Retries after a technical failure | Of an agent run",
         "maxExecutionHours | Time per agent run | Limit of one agent run"],
        ["Housekeeping",
         "finishedWindowDays | Show finished epics for | 1 to 30 days",
         "githubCallTimeoutSeconds | GitHub call timeout | Each short call",
         "logLevel | Log level | How much Carrier writes to its log"],
    ])
}

@Test func everyKeyOfTheEngineConfigAppearsExactlyOnce() {
    let keys = Mirror(reflecting: EngineConfig()).children.compactMap(\.label)
    #expect(keys.count == 9)
    #expect(behaviorGroups(bundle: english.bundle, locale: english.locale).flatMap(\.rows).map(\.key).sorted() == keys.sorted())
}

@Test func leadRoundsIsReadFromTheFileCheckedLikeReviewRoundsAndTheLeadIsOnlyThereWhenTheFileHasOne() {
    let file = Data(#"{"limits":{"maxLeadRounds":5},"agents":{"leadReviewer":{"profile":"p"}}}"#.utf8)
    #expect(EngineConfig(json: file).maxLeadRounds == 5 && EngineConfig().maxLeadRounds == 3)
    #expect(fileHasLeadReviewer(json: file))
    #expect(fileHasLeadReviewer(json: Data(#"{"agents":{"author":{}}}"#.utf8)) == false)
    #expect(fileHasLeadReviewer(json: Data("[]".utf8)) == false)
    var config = EngineConfig()
    config.maxLeadRounds = 0
    #expect(Array(config.problems(bundle: english.bundle, locale: english.locale).keys) == ["maxLeadRounds"])
}
