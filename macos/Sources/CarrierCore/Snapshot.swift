import Foundation

// The engine's `PanelSnapshot` (src/status/types.ts), field for field. Times are ms since epoch.
// macos/Tests/Fixtures/snapshot.json, written by the engine's test, is what the tests decode.

public struct PanelSnapshot: Codable, Equatable {
    public struct Slots: Codable, Equatable {
        public var busy: Int
        public var total: Int
    }

    public struct QueuedEpic: Codable, Equatable {
        public var repo: String
        public var issue: Int
    }

    public struct DoneEpic: Codable, Equatable {
        public var repo: String
        public var issue: Int
        public var prNumber: Int?
        public var finishedAt: Int?
        public var executionId: String?
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
