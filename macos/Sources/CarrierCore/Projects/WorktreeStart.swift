import Foundation

// Where a new worktree is cut from (ADR 0037): the chat's `worktreeStart` in `chat.json`, written the way the session ages are (SessionAges.swift).
// The host reads the file at each plan, so a save is used with no restart.

/// `worktreeStart` of `chat.json`: `remote` is `origin/<branch>` as of the last fetch, `local` is the local branch.
public enum WorktreeStart: String, CaseIterable, Equatable {
    case remote, local

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        self == .remote ? Copy.projectsStartRemoteLatest(bundle: bundle, locale: locale) : Copy.projectsStartLocalBranch(bundle: bundle, locale: locale)
    }

    /// The branch picker's tab.
    public func tabTitle(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        self == .remote ? Copy.projectsStartTabRemote(bundle: bundle, locale: locale) : Copy.projectsStartTabLocal(bundle: bundle, locale: locale)
    }
}

/// The host's default (src/chat/config.ts); a value equal to it is left out of the file.
public let defaultWorktreeStart = WorktreeStart.remote

private let worktreeStartKey = "worktreeStart"

/// The start `chat.json` says; `remote` when the key is missing or is not one of the two values (the host refuses any other). nil `chatJSON` is no file yet.
public func worktreeStart(chatJSON: Data?) -> WorktreeStart {
    let object = chatJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    return (object?[worktreeStartKey] as? String).flatMap(WorktreeStart.init(rawValue:)) ?? defaultWorktreeStart
}

/// Why the row is off, in words; nil when it is on. A start only means something for a new worktree.
public func worktreeStartOffReason(workIn: WorkIn, bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    workIn == .baseFolder ? Copy.projectsStartOnlyNewWorktree(bundle: bundle, locale: locale) : nil
}
