import Foundation

// How long a session that nobody opens keeps its agent running: the chat's `idleCloseMinutes` in `chat.json`, written the way the worktree start is
// (WorktreeStart.swift). The host reads the file every few seconds, so a save is used with no restart, from the next time a session is named.

/// `idleCloseMinutes` of `chat.json`: the minutes an idle session that no request names stays open before the host closes its agent. The session stays
/// in the list as asleep and wakes with the next message; the one on screen is read all the time and stays.
public enum IdleClose: Int, CaseIterable, Equatable {
    case tenMinutes = 10, thirtyMinutes = 30, oneHour = 60

    public var title: String {
        switch self {
        case .tenMinutes: "10 minutes"
        case .thirtyMinutes: "30 minutes"
        case .oneHour: "1 hour"
        }
    }
}

/// The host's default (src/chat/config.ts); a value equal to it is left out of the file.
public let defaultIdleClose = IdleClose.tenMinutes

private let idleCloseKey = "idleCloseMinutes"

/// The time `chat.json` says; ten minutes when the key is missing or is not one of the three values (the host refuses any other). nil `chatJSON` is no file yet.
public func idleClose(chatJSON: Data?) -> IdleClose {
    let object = chatJSON.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
    return (object?[idleCloseKey] as? Int).flatMap(IdleClose.init(rawValue:)) ?? defaultIdleClose
}
