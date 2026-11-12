import Foundation

// The Behavior page of Settings (docs/specs/behavior-in-settings.md): the eight values of `EngineConfig` in three groups, with the
// title and description of each and the key it edits, then the Reset card. The view only draws this.

/// How a row is edited.
public enum BehaviorControl: Equatable {
    /// a number field with its unit; `minimum` is the least the engine takes
    case number(minimum: Int, unit: String?)
    /// a decimal number of minutes
    case minutes
    /// a number of hours or Unlimited
    case runTime
    case logLevel
}

public struct BehaviorRow: Equatable {
    /// the `EngineConfig` property the row edits (also the name its problem is reported under)
    public let key: String
    public let title: String
    public let detail: String
    public let control: BehaviorControl
}

public struct BehaviorGroup: Equatable {
    public let title: String
    public let rows: [BehaviorRow]
}

public let behaviorGroups: [BehaviorGroup] = [
    BehaviorGroup(title: "Pace", rows: [
        BehaviorRow(key: "pollIntervalMinutes", title: "Look for ready epics every", detail: "In minutes", control: .minutes),
        BehaviorRow(key: "maxConcurrentEpics", title: "Epics at once", detail: "Running at the same time", control: .number(minimum: 1, unit: nil)),
    ]),
    BehaviorGroup(title: "When something goes wrong", rows: [
        BehaviorRow(key: "maxReviews", title: "Review rounds before asking you", detail: "Then the epic waits for a person (needs-human)", control: .number(minimum: 1, unit: nil)),
        BehaviorRow(key: "maxExecutionRetries", title: "Retries after a technical failure", detail: "Of an agent run", control: .number(minimum: 0, unit: nil)),
        BehaviorRow(key: "maxExecutionHours", title: "Time per agent run", detail: "Limit of one agent run", control: .runTime),
    ]),
    BehaviorGroup(title: "Housekeeping", rows: [
        BehaviorRow(key: "finishedWindowDays", title: "Show finished epics for", detail: "1 to 30 days", control: .number(minimum: 1, unit: "days")),
        BehaviorRow(key: "githubCallTimeoutSeconds", title: "GitHub call timeout", detail: "Each short call", control: .number(minimum: 1, unit: "s")),
        BehaviorRow(key: "logLevel", title: "Log level", detail: "How much Carrier writes to its log", control: .logLevel),
    ]),
]

/// The last group of the page: one card that puts the eight values back to the engine's defaults (`EngineConfig()`).
public let behaviorReset = (group: "Reset", title: "Restore the defaults", detail: "Everything on this page goes back to how it came", button: "Reset")

/// The note under the title when nothing went wrong; what the engine does with a saved value is not decided here.
public let behaviorSavingNote = "Saved as you change them · Carrier reads these when it starts"
