import Foundation

// The eight values of `config.json` the app lets the person change: how often Carrier looks, how loud it logs and its limits.
// The rules are the engine's (src/config/schema.ts and load.ts); the engine reads them once, when it starts. Everything else
// in the file (repos, profiles, agents) is left as it is.

public struct EngineConfig: Equatable {
    public static let logLevels = ["debug", "info", "warn", "error"]

    public var pollIntervalMinutes = 5.0
    public var logLevel = "info"
    public var maxConcurrentEpics = 3
    public var maxReviews = 5
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
        maxExecutionRetries = (limits["maxExecutionRetries"] as? Int) ?? maxExecutionRetries
        if limits["maxExecutionHours"] as? String == "unlimited" { maxExecutionHours = nil }
        else { maxExecutionHours = (limits["maxExecutionHours"] as? Int) ?? maxExecutionHours }
        githubCallTimeoutSeconds = (limits["githubCallTimeoutSeconds"] as? Int) ?? githubCallTimeoutSeconds
        finishedWindowDays = (file["finishedWindowDays"] as? Int) ?? finishedWindowDays
    }

    /// What the engine would refuse, by field name; empty when the values are fine.
    public var problems: [String: String] {
        var found: [String: String] = [:]
        if pollIntervalMinutes.isFinite == false || pollIntervalMinutes <= 0 { found["pollIntervalMinutes"] = "Must be more than 0" }
        if Self.logLevels.contains(logLevel) == false { found["logLevel"] = "Must be one of \(Self.logLevels.joined(separator: ", "))" }
        if maxConcurrentEpics < 1 { found["maxConcurrentEpics"] = "Must be 1 or more" }
        if maxReviews < 1 { found["maxReviews"] = "Must be 1 or more" }
        if maxExecutionRetries < 0 { found["maxExecutionRetries"] = "Must be 0 or more" }
        if let hours = maxExecutionHours, hours < 1 { found["maxExecutionHours"] = "Must be 1 or more, or unlimited" }
        if githubCallTimeoutSeconds < 1 { found["githubCallTimeoutSeconds"] = "Must be 1 or more" }
        if (1...30).contains(finishedWindowDays) == false { found["finishedWindowDays"] = "Must be a whole number from 1 to 30" }
        return found
    }

    /// `json` with these values in it. A value equal to the engine's default is taken out of the file instead of written, so a
    /// file does not pin what the engine may change later. nil when `json` is not a JSON object or the values have problems:
    /// the app never makes a config file, it only edits the one `carrier init` made.
    public func applied(to json: Data) -> Data? {
        guard problems.isEmpty, var file = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
        let base = EngineConfig()
        func put(_ key: String, _ value: Any, differs: Bool, in object: inout [String: Any]) {
            if differs { object[key] = value } else { object.removeValue(forKey: key) }
        }
        put("pollIntervalMinutes", pollIntervalMinutes, differs: pollIntervalMinutes != base.pollIntervalMinutes, in: &file)
        put("logLevel", logLevel, differs: logLevel != base.logLevel, in: &file)
        put("finishedWindowDays", finishedWindowDays, differs: finishedWindowDays != base.finishedWindowDays, in: &file)
        var limits = file["limits"] as? [String: Any] ?? [:]
        put("maxConcurrentEpics", maxConcurrentEpics, differs: maxConcurrentEpics != base.maxConcurrentEpics, in: &limits)
        put("maxReviews", maxReviews, differs: maxReviews != base.maxReviews, in: &limits)
        put("maxExecutionRetries", maxExecutionRetries, differs: maxExecutionRetries != base.maxExecutionRetries, in: &limits)
        put("maxExecutionHours", maxExecutionHours ?? "unlimited", differs: maxExecutionHours != base.maxExecutionHours, in: &limits)
        put("githubCallTimeoutSeconds", githubCallTimeoutSeconds, differs: githubCallTimeoutSeconds != base.githubCallTimeoutSeconds, in: &limits)
        if limits.isEmpty { file.removeValue(forKey: "limits") } else { file["limits"] = limits }
        return try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}
