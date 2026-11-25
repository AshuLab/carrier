import Foundation

// What the app does about a chat host older than the installed `carrier`. Stopping a host closes its agents' processes and the work
// in them, so only a host with no session working or waiting is replaced.

public enum HostReplacement: Equatable { case keep, replace, askRestart }

/// Numbers separated by dots, nil for anything else (empty, `unknown`, `1.2-beta`). Surrounding whitespace is dropped, so the line
/// `carrier --version` prints reads as it is.
public func versionNumbers(_ text: String) -> [Int]? {
    let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
    let numbers = parts.compactMap { $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) ? Int($0) : nil }
    return numbers.count == parts.count ? numbers : nil
}

/// What decides whether `carrier --version` can answer again: each path resolved through its symbolic links, with its modification date and
/// size; nil when one is missing, or when no path is given.
public func programStamp(_ paths: [String]) -> String? {
    guard paths.isEmpty == false else { return nil }
    var parts: [String] = []
    for path in paths {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved),
            let modified = attributes[.modificationDate] as? Date, let size = attributes[.size] as? NSNumber
        else { return nil }
        parts.append("\(resolved)|\(modified.timeIntervalSince1970)|\(size)")
    }
    return parts.joined(separator: "\n")
}

/// The version `run` reads, kept in `defaults` with the stamp of the files that printed it and given back without running while the stamp is the
/// same. Nothing is kept for a run that failed (nil), for no stamp (a program that is not remembered), or when the stamp changed while it ran:
/// what was read may belong to the new file, and the next look reads it again.
public func rememberedVersion(stamp: () -> String?, defaults: UserDefaults = .standard, run: () async -> String?) async -> String? {
    let before = stamp()
    if let before, let kept = defaults.dictionary(forKey: Preference.carrierInstalledVersion.name) as? [String: String], kept["stamp"] == before, let version = kept["version"] { return version }
    guard let version = await run() else { return nil }
    if let before, stamp() == before { defaults.set(["stamp": before, "version": version], forKey: Preference.carrierInstalledVersion.name) }
    return version
}

/// A version that cannot be read, on either side, is never older: the host stays. `1.2` and `1.2.0` are the same.
public func hostReplacement(running: String, installed: String, working: Bool) -> HostReplacement {
    guard var older = versionNumbers(running), var newer = versionNumbers(installed) else { return .keep }
    let length = max(older.count, newer.count)
    older += Array(repeating: 0, count: length - older.count)
    newer += Array(repeating: 0, count: length - newer.count)
    guard older.lexicographicallyPrecedes(newer) else { return .keep }
    return working ? .askRestart : .replace
}

/// What the app does about an engine older than the installed `carrier`: leave it, pause intake until its executions end, or replace it.
public enum EngineReplacement: Equatable { case keep, pauseAndWait, replace }

/// The host's comparison, with executions in flight where the host has a session working: an engine that is working is not stopped.
public func engineReplacement(running: String, installed: String, executionsInFlight: Int) -> EngineReplacement {
    switch hostReplacement(running: running, installed: installed, working: executionsInFlight > 0) {
    case .keep: .keep
    case .askRestart: .pauseAndWait
    case .replace: .replace
    }
}

/// What the Sessions section and the Sessions home say while an older host is left running because a session is working.
public func chatHostRestartNotice(bundle: Bundle? = nil, locale: Locale = .current) -> ChatHostNotice {
    ChatHostNotice(title: Copy.lifecycleChatHostOlderTitle(bundle: bundle, locale: locale), line: Copy.lifecycleChatHostOlderLine(bundle: bundle, locale: locale))
}
