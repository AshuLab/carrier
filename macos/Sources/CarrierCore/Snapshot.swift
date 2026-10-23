import Foundation

// The engine's `PanelSnapshot` (src/status/types.ts), field for field. Times are ms since epoch.
// macos/Tests/Fixtures/snapshot.json, written by the engine's test, is what the tests decode.
// Every field the redesign added is optional: an engine that predates it sends none of them (snapshot-old-engine.json).

public struct PanelSnapshot: Codable, Equatable {
    public struct Slots: Codable, Equatable {
        public var busy: Int
        public var total: Int
    }

    public struct QueuedEpic: Codable, Equatable {
        public var repo: String
        public var issue: Int
        public var title: String?
        public var queuedAt: Int?
    }

    public struct Agent: Codable, Equatable {
        public var harness: String
        public var model: String
        public var provider: String?
    }

    public struct Agents: Codable, Equatable {
        public var author: Agent
        public var reviewer: Agent
    }

    public struct Engine: Codable, Equatable {
        public struct RateLimit: Codable, Equatable {
            public var remaining: Int
            public var limit: Int
            public var resetAt: Int
            public var profile: String
        }

        public var version: String
        public var pollIntervalMs: Int
        public var maxConcurrentEpics: Int
        public var rateLimit: RateLimit?
    }

    public struct Watched: Codable, Equatable {
        public var repo: String
        public var lastCheckedAt: Int?
        public var ok: Bool
        public var error: String?
        public var agents: Agents
    }

    public struct Session: Codable, Equatable {
        public struct Last: Codable, Equatable {
            public var kind: String
            public var text: String
            public var at: Int
        }

        public var executionId: String
        public var repo: String
        public var issue: Int
        public var stage: PanelEpic.Stage
        public var round: Int?
        public var harness: String
        public var model: String
        public var startedAt: Int
        public var last: Last?
    }

    public struct DoneEpic: Codable, Equatable {
        public var repo: String
        public var issue: Int
        public var prNumber: Int?
        public var finishedAt: Int?
        public var executionId: String?
        /// The issue's title; an engine that does not send it for finished epics leaves nil and the header says "Epic #N".
        public var title: String?
    }

    /// A merged or cancelled epic that ended inside the engine's finished window.
    public struct FinishedEpic: Codable, Equatable {
        public enum Status: String, Codable {
            case merged, cancelled
        }

        public var repo: String
        public var issue: Int
        public var title: String?
        public var labels: [String]
        public var prNumber: Int?
        public var finishedAt: Int
        public var status: Status
        /// The stored reason; nil when merged.
        public var cancelReason: String?
        public var executionId: String?

        /// The same epic as a ready-for-test one, for what is drawn from a `DoneEpic` (links, the details tab).
        public var asDone: DoneEpic {
            DoneEpic(repo: repo, issue: issue, prNumber: prNumber, finishedAt: finishedAt, executionId: executionId, title: title)
        }
    }

    public var now: Int
    public var slots: Slots
    public var queue: [QueuedEpic]
    public var epics: [PanelEpic]
    public var startedAt: Int
    public var repos: Int
    public var nextCheckAt: Int?
    public var problem: String?
    public var paused: Bool
    public var done: [DoneEpic]
    public var engine: Engine?
    public var watched: [Watched]?
    public var sessions: [Session]?
    /// Newest first. An engine that predates the field sends none: decoded as empty.
    public var finished: [FinishedEpic] = []
}

extension PanelSnapshot {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        now = try c.decode(Int.self, forKey: .now)
        slots = try c.decode(Slots.self, forKey: .slots)
        queue = try c.decode([QueuedEpic].self, forKey: .queue)
        epics = try c.decode([PanelEpic].self, forKey: .epics)
        startedAt = try c.decode(Int.self, forKey: .startedAt)
        repos = try c.decode(Int.self, forKey: .repos)
        nextCheckAt = try c.decodeIfPresent(Int.self, forKey: .nextCheckAt)
        problem = try c.decodeIfPresent(String.self, forKey: .problem)
        paused = try c.decode(Bool.self, forKey: .paused)
        done = try c.decode([DoneEpic].self, forKey: .done)
        engine = try c.decodeIfPresent(Engine.self, forKey: .engine)
        watched = try c.decodeIfPresent([Watched].self, forKey: .watched)
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions)
        finished = try c.decodeIfPresent([FinishedEpic].self, forKey: .finished) ?? []
    }
}

public struct PanelEpic: Codable, Equatable {
    public enum Status: String, Codable {
        case running
        case needsHuman = "needs_human"
    }

    public enum Stage: String, Codable {
        case ship, review, fix
    }

    public struct Slices: Codable, Equatable {
        public var done: Int
        public var total: Int
    }

    public var repo: String
    public var issue: Int
    public var status: Status
    public var stage: Stage?
    public var round: Int?
    public var maxReviews: Int
    public var blockers: Int
    public var stageSince: Int
    public var lastActivityAt: Int?
    public var issueUrl: String
    public var prUrl: String?
    public var lastError: String?
    public var needsHumanReason: String?
    public var slices: Slices?
    public var executionId: String?
    public var title: String?
    public var labels: [String]?
    public var queuedAt: Int?
    public var startedAt: Int?
    public var finishedAt: Int?
    public var branch: String?
    public var workspace: String?
    /// One of review_limit, agent_needs_human, retries_exhausted, timeout, auth, workspace, pr_invalid; a string so a kind added later does not break the panel.
    public var needsHumanKind: String?
    public var blockerTitles: [String]?
    public var agents: PanelSnapshot.Agents?
}

/// Why a snapshot did not decode; `field` is the path of the offending value, like `epics.0.slices.total`.
public enum SnapshotError: Error, Equatable {
    case missingField(String)
    case wrongType(String)
    case malformed
}

public func decodeSnapshot(_ data: Data) throws -> PanelSnapshot {
    func path(_ context: DecodingError.Context, _ key: CodingKey? = nil) -> String {
        (context.codingPath + (key.map { [$0] } ?? [])).map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }
    do {
        return try JSONDecoder().decode(PanelSnapshot.self, from: data)
    } catch DecodingError.keyNotFound(let key, let context) {
        throw SnapshotError.missingField(path(context, key))
    } catch DecodingError.valueNotFound(_, let context) {
        throw SnapshotError.missingField(path(context))
    } catch DecodingError.typeMismatch(_, let context) {
        throw SnapshotError.wrongType(path(context))
    } catch DecodingError.dataCorrupted(let context) where context.codingPath.isEmpty == false {
        throw SnapshotError.wrongType(path(context))
    } catch is DecodingError {
        throw SnapshotError.malformed
    }
}
