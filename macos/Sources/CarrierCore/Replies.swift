import Foundation

// What the engine's `sessions`, `events`, `epic` and `files` requests answer in `data` (src/control/replies.ts), field for field.
// Times are ms since epoch. Kinds, states and marks are strings so a value added later does not stop a reply from decoding;
// a field the engine may send as null or leave out is optional. The engine's test writes macos/Tests/Fixtures/reply-*.json.

public struct SessionsReply: Codable, Equatable {
    public struct Session: Codable, Equatable {
        public var executionId: String
        public var stage: String
        public var role: String
        public var round: Int?
        public var agent: PanelSnapshot.Agent
        public var status: String
        public var startedAt: Int
        public var finishedAt: Int?
        /// nil while the session runs.
        public var resume: ResumeDescriptor?
    }

    /// Newest first.
    public var sessions: [Session]
}

/// Not yet validated: the app checks it before it builds a command (ADR 0007).
public struct ResumeDescriptor: Codable, Equatable {
    public var harness: String
    public var sessionId: String
    public var cwd: String
    public var configDir: String?
}

public struct ExecEvent: Codable, Equatable {
    public struct DiffLine: Codable, Equatable {
        public var sign: String
        public var text: String
    }

    public var id: Int
    public var at: Int
    public var kind: String
    public var text: String?
    public var callId: String?
    public var agentId: String?
    public var tool: String?
    public var arg: String?
    public var summary: String?
    public var status: String?
    public var durationMs: Int?
    public var output: [String]?
    public var diff: [DiffLine]?
}

public struct EventsReply: Codable, Equatable {
    public var events: [ExecEvent]
    /// The `after` of the next request.
    public var next: Int
    public var running: Bool
    /// false when the harness has no parser yet: the app falls back to `tail`.
    public var structured: Bool

    public init(events: [ExecEvent], next: Int, running: Bool, structured: Bool) {
        self.events = events
        self.next = next
        self.running = running
        self.structured = structured
    }
}

public struct EpicReply: Codable, Equatable {
    public struct Stage: Codable, Equatable {
        public var stage: String
        public var startedAt: Int
        public var endedAt: Int?
    }

    public struct Blocker: Codable, Equatable {
        public var id: String?
        public var title: String
        public var url: String?
        public var mark: String
        public var approximate: Bool
    }

    public struct Commit: Codable, Equatable {
        public var sha: String
        public var subject: String
    }

    public struct Round: Codable, Equatable {
        public var round: Int
        public var reviewer: PanelSnapshot.Agent
        public var verdict: String
        public var blockers: [Blocker]
        public var reviewMs: Int?
        public var fixMs: Int?
        public var reviewedSha: String?
        public var fixedSha: String?
        public var commits: [Commit]
    }

    public struct Slice: Codable, Equatable {
        public var number: Int
        public var title: String
        public var state: String
        public var blockedBy: [Int]
        public var prNumber: Int?
        public var closedAt: Int?
        public var readAt: Int
        /// Hints for a slice in progress; the engine does not send them yet (docs/specs/macos-app-redesign.md, spike 3).
        public var lane: Int? = nil
        public var activity: String? = nil
    }

    public struct Worktree: Codable, Equatable {
        public var kind: String
        public var lane: Int?
        public var path: String
    }

    public struct Checks: Codable, Equatable {
        public var passing: Int
        public var failing: Int
        public var pending: Int
    }

    public struct PullRequest: Codable, Equatable {
        public var number: Int
        public var url: String
        public var draft: Bool
        public var mergeState: String
        public var reviewDecision: String?
        /// nil when the pull request has no checks, which is not the same as pending.
        public var checks: Checks?
    }

    public var stages: [Stage]
    public var rounds: [Round]
    public var slices: [Slice]
    public var worktrees: [Worktree]
    public var branch: String?
    /// nil during ship.
    public var pr: PullRequest?
}

public struct FilesReply: Codable, Equatable {
    public struct File: Codable, Equatable {
        public var path: String
        public var added: Int
        public var removed: Int
        /// The ids of the other sections that touch this file.
        public var alsoIn: [String]
    }

    public struct Section: Codable, Equatable {
        public var id: String
        public var kind: String
        public var title: String
        public var added: Int
        public var removed: Int
        public var files: [File]
    }

    public var sections: [Section]
}
