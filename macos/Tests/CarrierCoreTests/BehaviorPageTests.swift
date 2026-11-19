import Testing
@testable import CarrierCore

@Test func theBehaviorPageHasThreeGroupsWithTheirTitlesDescriptionsAndKeys() {
    let listed = behaviorGroups.map { group in
        [group.title] + group.rows.map { "\($0.key) | \($0.title) | \($0.detail)" }
    }
    #expect(listed == [
        ["Pace",
         "pollIntervalMinutes | Look for ready epics every | In minutes",
         "maxConcurrentEpics | Epics at once | Running at the same time"],
        ["When something goes wrong",
         "maxReviews | Review rounds before asking you | Then the epic waits for a person (needs-human)",
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
    #expect(keys.count == 8)
    #expect(behaviorGroups.flatMap(\.rows).map(\.key).sorted() == keys.sorted())
}
