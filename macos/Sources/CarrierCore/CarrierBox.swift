import Foundation

// The Overview's Carrier box and its watched repositories (docs/specs/macos-app-redesign.md, story 16), as plain values.
// The wording comes from PanelFormat so the window and the terminal panel say the same things.

public struct CarrierBox: Equatable {
    public struct Row: Equatable {
        public var label: String
        public var value: String
    }

    public struct Intake: Equatable {
        public var paused: Bool
        public var value: String { paused ? "Paused" : "Active" }
        public var actionTitle: String { paused ? "Resume" : "Pause" }
        /// The existing control command the link sends.
        public var command: Command { paused ? .resume : .pause }
    }

    public enum Status: Equatable {
        /// Checked on every cycle.
        case watching
        /// Intake is paused: the repository is not looked at until it resumes.
        case paused
        /// The last check failed.
        case failing
    }

    public struct Repo: Equatable {
        public var name: String
        /// The repository on GitHub, without the scheme: "github.com/owner/name".
        public var url: String
        public var status: Status
        public var ok: Bool
        /// "40s ago"; what the snapshot says went wrong when the last check failed.
        public var lastCheck: String
        public var error: String?
    }

    public var title = "Carrier running"
    public var uptime: String
    /// The engine's own problem (GitHub not answering, ...), absent when there is none.
    public var problem: String?
    /// Next check, then the rate limit only when the snapshot has one.
    public var rows: [Row]
    public var intake: Intake
    /// Empty for an engine that predates the field.
    public var repos: [Repo]
    public var repoCount: Int
}

public func carrierBox(_ snapshot: PanelSnapshot) -> CarrierBox {
    var rows = [CarrierBox.Row(label: "Next check", value: nextCheckLine(snapshot).replacingOccurrences(of: "next check ", with: ""))]
    if let limit = snapshot.engine?.rateLimit {
        let number = IntegerFormatStyle<Int>.number.locale(Locale(identifier: "en_US"))
        let reset = limit.resetAt <= snapshot.now ? "reset" : "resets in \(formatDuration(limit.resetAt - snapshot.now))"
        rows.append(.init(
            label: "GitHub rate limit (\(limit.profile) profile)",
            value: "\(limit.remaining.formatted(number)) / \(limit.limit.formatted(number)) · \(reset)"
        ))
    }
    let repos = (snapshot.watched ?? []).map { watched in
        CarrierBox.Repo(
            name: watched.repo,
            url: "github.com/\(watched.repo)",
            status: watched.ok ? (snapshot.paused ? .paused : .watching) : .failing,
            ok: watched.ok,
            lastCheck: watched.lastCheckedAt.map { agoLine($0, now: snapshot.now) } ?? "not checked yet",
            error: watched.ok ? nil : (watched.error ?? "the last check failed")
        )
    }
    return CarrierBox(
        uptime: uptimeLine(snapshot), problem: snapshot.problem, rows: rows,
        intake: .init(paused: snapshot.paused), repos: repos, repoCount: snapshot.watched?.count ?? snapshot.repos
    )
}
