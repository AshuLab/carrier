import Foundation

// What the engine's `sessions`, `events`, `epic`, `files` and `fileDiff` requests answer in `data` (src/control/replies.ts), field for field.
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
        /// What the agent reported when it ended; nil while no result was imported, and for an engine that does not send it.
        public var result: SessionResult?
    }

    /// Newest first.
    public var sessions: [Session]
}

/// The engine has already redacted and cut the text.
public struct SessionResult: Codable, Equatable {
    public struct Verification: Codable, Equatable {
        public var ci: String
        public var evidence: String
    }

    public var outcome: String
    public var summary: String
    /// Only a completed result has one.
    public var verification: Verification?
    /// needs_human only.
    public var reason: String?
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

    /// A non-blocking finding a completed review listed.
    public struct Observation: Codable, Equatable {
        public var id: String?
        public var title: String
        public var url: String?
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
        /// Empty when the review listed none, and for an engine that predates the field.
        public var observations: [Observation] = []
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
        /// Hints for a slice in progress (docs/specs/macos-app-redesign.md, spike 3); absent from an older engine, null when the stream gave none.
        public var lane: Int? = nil
        public var activity: String? = nil
        /// The pull request's state (`open`, `draft`, `merged` or `closed`) and merge time; null with no pull request, absent from an older engine.
        public var prState: String? = nil
        public var prMergedAt: Int? = nil
    }

    /// A review thread of the final pull request, a cache of GitHub in GitHub's order.
    public struct ReviewThread: Codable, Equatable {
        public var id: String
        public var path: String
        /// nil when the thread is outdated and GitHub no longer maps it.
        public var line: Int?
        public var resolved: Bool
        public var outdated: Bool
        /// nil for a deleted account.
        public var author: String?
        public var bot: Bool
        /// The opening comment's first line, cut by the engine; empty when the comment is.
        public var firstLine: String
        public var commentCount: Int
        /// The opening comment's url.
        public var url: String
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
    /// True when the epic has more slices than the list holds (only the first hundred are read); absent from an older engine.
    public var slicesTruncated: Bool? = nil
    /// nil when the engine does not send threads (hides the section); an empty list means the pull request has none.
    public var threads: [ReviewThread]? = nil
    /// True when the pull request has more threads than the list holds (only the first hundred are read); absent from an older engine.
    public var threadsTruncated: Bool? = nil
    public var worktrees: [Worktree]
    public var branch: String?
    /// nil during ship.
    public var pr: PullRequest?
}

extension EpicReply.Round {
    /// An engine that predates `observations` leaves it out: none, not an error.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        round = try values.decode(Int.self, forKey: .round)
        reviewer = try values.decode(PanelSnapshot.Agent.self, forKey: .reviewer)
        verdict = try values.decode(String.self, forKey: .verdict)
        blockers = try values.decode([EpicReply.Blocker].self, forKey: .blockers)
        observations = try values.decodeIfPresent([EpicReply.Observation].self, forKey: .observations) ?? []
        reviewMs = try values.decodeIfPresent(Int.self, forKey: .reviewMs)
        fixMs = try values.decodeIfPresent(Int.self, forKey: .fixMs)
        reviewedSha = try values.decodeIfPresent(String.self, forKey: .reviewedSha)
        fixedSha = try values.decodeIfPresent(String.self, forKey: .fixedSha)
        commits = try values.decode([EpicReply.Commit].self, forKey: .commits)
    }
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

    public struct Total: Codable, Equatable {
        public var files: Int
        public var added: Int
        public var removed: Int
    }

    public var sections: [Section]
    /// The epic branch against the default branch; nil when git cannot say. Absent from an older engine.
    public var total: Total? = nil
    /// Files were left out to keep the reply small; absent from an older engine.
    public var truncated: Bool? = nil
}

/// The edited fragments of one file of a card. A row's sign is `+`, `-`, ` ` or `@`: a hunk separator whose text is git's `@@ -a,b +c,d @@`.
public struct FileDiffReply: Codable, Equatable {
    public var rows: [ExecEvent.DiffLine]
    /// The rows were cut at the engine's cap.
    public var truncated: Bool
    /// `binary`, `too-big` or `no-changes`, with no rows, when there is nothing to draw.
    public var note: String?
}
