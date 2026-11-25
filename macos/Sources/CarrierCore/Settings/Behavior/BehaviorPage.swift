import Foundation

// The Behavior page of Settings (docs/specs/behavior-in-settings.md): the eight values of `EngineConfig` in three groups, with the
// title and description of each and the key it edits, then the Reset card. The view only draws this.

/// How a row is edited.
public enum BehaviorControl: Equatable {
    /// a number field; `minimum` is the least the engine takes
    case number(minimum: Int)
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
    /// the unit said after the number field (`min`, `days`, `s`, `h`), in the language it is asked in; nil when the row has none
    public let unit: String?
}

public struct BehaviorGroup: Equatable {
    /// what the group is known by in Settings (its anchor), whatever its title says
    public let id: String
    public let title: String
    public let rows: [BehaviorRow]
}

public func behaviorGroups(bundle: Bundle? = nil, locale: Locale = .current) -> [BehaviorGroup] {
    [
        BehaviorGroup(id: "pace", title: Copy.behaviorPace(bundle: bundle, locale: locale), rows: [
            BehaviorRow(
                key: "pollIntervalMinutes", title: Copy.behaviorPollTitle(bundle: bundle, locale: locale), detail: Copy.behaviorPollDetail(bundle: bundle, locale: locale),
                control: .minutes, unit: Copy.behaviorUnit(which: .minutes, bundle: bundle, locale: locale)),
            BehaviorRow(
                key: "maxConcurrentEpics", title: Copy.behaviorConcurrentTitle(bundle: bundle, locale: locale), detail: Copy.behaviorConcurrentDetail(bundle: bundle, locale: locale),
                control: .number(minimum: 1), unit: nil),
        ]),
        BehaviorGroup(id: "when-something-goes-wrong", title: Copy.behaviorWrong(bundle: bundle, locale: locale), rows: [
            BehaviorRow(
                key: "maxReviews", title: Copy.behaviorReviewsTitle(bundle: bundle, locale: locale), detail: Copy.behaviorReviewsDetail(bundle: bundle, locale: locale),
                control: .number(minimum: 1), unit: nil),
            BehaviorRow(
                key: "maxExecutionRetries", title: Copy.behaviorRetriesTitle(bundle: bundle, locale: locale), detail: Copy.behaviorRetriesDetail(bundle: bundle, locale: locale),
                control: .number(minimum: 0), unit: nil),
            BehaviorRow(
                key: "maxExecutionHours", title: Copy.behaviorRunTimeTitle(bundle: bundle, locale: locale), detail: Copy.behaviorRunTimeDetail(bundle: bundle, locale: locale),
                control: .runTime, unit: Copy.behaviorUnit(which: .hours, bundle: bundle, locale: locale)),
        ]),
        BehaviorGroup(id: "housekeeping", title: Copy.behaviorHousekeeping(bundle: bundle, locale: locale), rows: [
            BehaviorRow(
                key: "finishedWindowDays", title: Copy.behaviorFinishedTitle(bundle: bundle, locale: locale), detail: Copy.behaviorFinishedDetail(bundle: bundle, locale: locale),
                control: .number(minimum: 1), unit: Copy.behaviorUnit(which: .days, bundle: bundle, locale: locale)),
            BehaviorRow(
                key: "githubCallTimeoutSeconds", title: Copy.behaviorTimeoutTitle(bundle: bundle, locale: locale), detail: Copy.behaviorTimeoutDetail(bundle: bundle, locale: locale),
                control: .number(minimum: 1), unit: Copy.behaviorUnit(which: .seconds, bundle: bundle, locale: locale)),
            BehaviorRow(
                key: "logLevel", title: Copy.behaviorLogTitle(bundle: bundle, locale: locale), detail: Copy.behaviorLogDetail(bundle: bundle, locale: locale),
                control: .logLevel, unit: nil),
        ]),
    ]
}

