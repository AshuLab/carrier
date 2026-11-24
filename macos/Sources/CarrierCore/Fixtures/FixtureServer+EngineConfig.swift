import Foundation

// `setWatchedRepos` and `editBehavior` as the real engine answers them (src/config/engine-edit.ts), against the fixture home's `engine.json`: the file is read again, the change applied to its raw
// JSON (every other key and every other repo's fields stay), checked with the words and kinds Node gives, and written only when all hold. The reply is `engine: "applied"`: there is no engine to
// run on the file. A change that would make the whole file invalid in a way only the engine's full schema sees is not refused here.

extension FixtureServer {
    func engineConfigReply(_ id: Int, _ request: [String: Any]) -> Data? {
        let url = URL(fileURLWithPath: CarrierPlaces(folder: home).engineConfig)
        func refusal(_ path: String, _ problem: String, _ words: String) -> Data {
            Self.refused(id, "config.problem", words, ["path": .string(path), "problem": .string(problem)])
        }
        guard let current = try? Data(contentsOf: url) else { return refusal("(file)", "notFound", "\(url.path) is not there, so it was not changed") }
        guard var file = (try? JSONSerialization.jsonObject(with: current)) as? [String: Any] else {
            return refusal("(file)", "notAnObject", "\(url.path) is not a JSON object, so it was not changed")
        }
        var saved: [String: Any] = [:]
        switch request["cmd"] as? String {
        case "setWatchedRepos":
            guard let names = request["repos"] as? [String] else { return nil }
            for (index, name) in names.enumerated() {
                guard let problem = repoProblem(name, joining: Array(names[..<index])) else { continue }
                let kind = isRepoName(name) == false ? "notARepo" : problem.hasSuffix("is already watched") ? "alreadyWatched" : "sameFolderName"
                return refusal("repos[\(index)]", kind, problem)
            }
            let kept = file["repos"] as? [[String: Any]] ?? []
            let repos = names.map { name in kept.first { $0["name"] as? String == name } ?? ["name": name] }
            file["repos"] = repos
            saved["repos"] = repos
        case "editBehavior":
            guard let changes = request["changes"] as? [String: Any] else { return nil }
            var config = EngineConfig(json: current)
            let limits = changes["limits"] as? [String: Any] ?? [:]
            config.pollIntervalMinutes = (changes["pollIntervalMinutes"] as? Double) ?? config.pollIntervalMinutes
            config.logLevel = (changes["logLevel"] as? String) ?? config.logLevel
            config.finishedWindowDays = (changes["finishedWindowDays"] as? Int) ?? config.finishedWindowDays
            config.maxConcurrentEpics = (limits["maxConcurrentEpics"] as? Int) ?? config.maxConcurrentEpics
            config.maxReviews = (limits["maxReviews"] as? Int) ?? config.maxReviews
            config.maxExecutionRetries = (limits["maxExecutionRetries"] as? Int) ?? config.maxExecutionRetries
            config.githubCallTimeoutSeconds = (limits["githubCallTimeoutSeconds"] as? Int) ?? config.githubCallTimeoutSeconds
            if limits["maxExecutionHours"] as? String == "unlimited" { config.maxExecutionHours = nil } else if let hours = limits["maxExecutionHours"] as? Int { config.maxExecutionHours = hours }
            if let (key, words) = config.problems.sorted(by: { $0.key < $1.key }).first {
                let path = ["pollIntervalMinutes", "logLevel", "finishedWindowDays"].contains(key) ? key : "limits.\(key)"
                return refusal(path, "invalid", words)
            }
            let base = EngineConfig()
            func put(_ key: String, _ value: Any, differs: Bool, in object: inout [String: Any]) {
                if differs { object[key] = value } else { object.removeValue(forKey: key) }
            }
            put("pollIntervalMinutes", config.pollIntervalMinutes, differs: config.pollIntervalMinutes != base.pollIntervalMinutes, in: &file)
            put("logLevel", config.logLevel, differs: config.logLevel != base.logLevel, in: &file)
            put("finishedWindowDays", config.finishedWindowDays, differs: config.finishedWindowDays != base.finishedWindowDays, in: &file)
            var own = file["limits"] as? [String: Any] ?? [:]
            put("maxConcurrentEpics", config.maxConcurrentEpics, differs: config.maxConcurrentEpics != base.maxConcurrentEpics, in: &own)
            put("maxReviews", config.maxReviews, differs: config.maxReviews != base.maxReviews, in: &own)
            put("maxExecutionRetries", config.maxExecutionRetries, differs: config.maxExecutionRetries != base.maxExecutionRetries, in: &own)
            put("maxExecutionHours", config.maxExecutionHours ?? "unlimited", differs: config.maxExecutionHours != base.maxExecutionHours, in: &own)
            put("githubCallTimeoutSeconds", config.githubCallTimeoutSeconds, differs: config.githubCallTimeoutSeconds != base.githubCallTimeoutSeconds, in: &own)
            file["limits"] = own.isEmpty ? nil : own
            for key in changes.keys where key != "limits" { saved[key] = file[key] }
            saved = saved.compactMapValues { $0 }
            if limits.isEmpty == false, let own = file["limits"] as? [String: Any] {
                let kept = limits.keys.reduce(into: [String: Any]()) { $0[$1] = own[$1] }.compactMapValues { $0 }
                if kept.isEmpty == false { saved["limits"] = kept }
            }
        default:
            return nil
        }
        guard let data = try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), (try? data.write(to: url, options: .atomic)) != nil else {
            return Self.refused(id, "request.internal", "internal error")
        }
        return Self.answer(id, ["saved": saved, "engine": "applied"])
    }
}
