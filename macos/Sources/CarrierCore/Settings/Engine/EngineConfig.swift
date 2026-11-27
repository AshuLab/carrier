import Foundation

// The nine values of `engine.json` the app lets the person change: how often Carrier looks, how loud it logs and its limits.
// The rules are the engine's (src/config/schema.ts and load.ts), checked here while the person types; the file is written by the engine, or by `carrier config`
// (`EngineConfigChange.behavior`, `src/config/engine-edit.ts`), which leave everything else in it (repos, profiles, agents) as it is.

public struct EngineConfig: Equatable, Sendable {
    public static let logLevels = ["debug", "info", "warn", "error"]

    public var pollIntervalMinutes = 5.0
    public var logLevel = "info"
    public var maxConcurrentEpics = 3
    public var maxReviews = 5
    public var maxLeadRounds = 3
    public var maxExecutionRetries = 3
    /// nil is `"unlimited"`
    public var maxExecutionHours: Int? = 4
    public var githubCallTimeoutSeconds = 30
    /// How many days a merged or cancelled epic stays in view
    public var finishedWindowDays = 15

    public init() {}

    /// The values in the file, the engine's default for each one it does not have.
    public init(json: Data) {
        let file = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
        let limits = file["limits"] as? [String: Any] ?? [:]
        self.init()
        pollIntervalMinutes = (file["pollIntervalMinutes"] as? Double) ?? pollIntervalMinutes
        logLevel = (file["logLevel"] as? String) ?? logLevel
        maxConcurrentEpics = (limits["maxConcurrentEpics"] as? Int) ?? maxConcurrentEpics
        maxReviews = (limits["maxReviews"] as? Int) ?? maxReviews
        maxLeadRounds = (limits["maxLeadRounds"] as? Int) ?? maxLeadRounds
        maxExecutionRetries = (limits["maxExecutionRetries"] as? Int) ?? maxExecutionRetries
        if limits["maxExecutionHours"] as? String == "unlimited" { maxExecutionHours = nil }
        else { maxExecutionHours = (limits["maxExecutionHours"] as? Int) ?? maxExecutionHours }
        githubCallTimeoutSeconds = (limits["githubCallTimeoutSeconds"] as? Int) ?? githubCallTimeoutSeconds
        finishedWindowDays = (file["finishedWindowDays"] as? Int) ?? finishedWindowDays
    }

    /// What the engine would refuse, by field name; empty when the values are fine.
    public func problems(bundle: Bundle? = nil, locale: Locale = .current) -> [String: String] {
        var found: [String: String] = [:]
        if pollIntervalMinutes.isFinite == false || pollIntervalMinutes <= 0 { found["pollIntervalMinutes"] = Copy.engineMustBeOverZero(bundle: bundle, locale: locale) }
        if Self.logLevels.contains(logLevel) == false { found["logLevel"] = Copy.engineMustBeOneOf(levels: Self.logLevels.joined(separator: ", "), bundle: bundle, locale: locale) }
        if maxConcurrentEpics < 1 { found["maxConcurrentEpics"] = Copy.engineMustBeAtLeast(minimum: 1, bundle: bundle, locale: locale) }
        if maxReviews < 1 { found["maxReviews"] = Copy.engineMustBeAtLeast(minimum: 1, bundle: bundle, locale: locale) }
        if maxLeadRounds < 1 { found["maxLeadRounds"] = Copy.engineMustBeAtLeast(minimum: 1, bundle: bundle, locale: locale) }
        if maxExecutionRetries < 0 { found["maxExecutionRetries"] = Copy.engineMustBeAtLeast(minimum: 0, bundle: bundle, locale: locale) }
        if let hours = maxExecutionHours, hours < 1 { found["maxExecutionHours"] = Copy.engineHoursOrUnlimited(bundle: bundle, locale: locale) }
        if githubCallTimeoutSeconds < 1 { found["githubCallTimeoutSeconds"] = Copy.engineMustBeAtLeast(minimum: 1, bundle: bundle, locale: locale) }
        if (1...30).contains(finishedWindowDays) == false { found["finishedWindowDays"] = Copy.engineDaysRange(bundle: bundle, locale: locale) }
        return found
    }
}
