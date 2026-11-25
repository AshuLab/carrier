import Foundation

// The Agent output tab's list: one section per agent session of an epic, oldest first (the newest at the bottom), built from the `sessions` reply and the
// events fetched so far (docs/specs/macos-app-redesign.md, story 19). The views map it one to one.

// MARK: sections

/// What the user folded or unfolded by hand; a section nobody touched follows its default.
public struct SessionFolds: Equatable {
    private var chosen: [String: Bool] = [:]
    /// The sections whose result row is open.
    private var resultOpen: Set<String> = []

    public init() {}

    public func isResultOpen(_ section: SessionSection) -> Bool { resultOpen.contains(section.id) }

    public mutating func toggleResult(_ section: SessionSection) {
        if resultOpen.insert(section.id).inserted == false { resultOpen.remove(section.id) }
    }

    public func isOpen(_ section: SessionSection) -> Bool { chosen[section.id] ?? section.openByDefault }

    public mutating func toggle(_ section: SessionSection) { chosen[section.id] = !isOpen(section) }
}

public struct SessionSection: Equatable, Identifiable {
    public enum State: Equatable { case running, stopped, done }

    public var id: String
    public var state: State
    /// "Claude", "Codex".
    public var agent: String
    /// The avatar's letter when the session has no profile (the mockup's: C for Claude, X for Codex).
    public var initial: String
    /// "Builder" (ship), "Reviewer", "Fixer".
    public var role: String
    /// "Ship", "Round 2".
    public var place: String
    /// nil when no events are known (the harness has no parser yet, or none has arrived): the header then has no counts.
    public var counts: SessionCounts?
    /// "since 16:09" while it runs, how long it took when it finished; nil for a stopped one, whose badge says it.
    public var timeLabel: String?
    /// Running and stopped open, finished folded; the newest one is open whatever it is.
    public var openByDefault: Bool
    /// What Continue in Terminal resumes; nil for a running session, whatever the engine sent (ADR 0007).
    public var resume: ResumeDescriptor?
    /// What the agent reported when it ended; nil when no result was imported.
    public var result: ResultCard?
    /// `killed: SIGKILL`, the failure kind and its detail as the header says them; nil when the session has no failure.
    public var failure: String?
    /// The role of `engine.json` the session ran as (`author`, `reviewer`), which says whose profile it acted as.
    public var engineRole = ""
    /// The engine's stage (`ship`, `review`, `fix`) and round, to find what the session answers or found.
    public var stage = ""
    public var round: Int?
    /// The GitHub profile it acted as (an Agent Forge bot); nil when neither the engine nor the config says.
    public var profile: String?
    /// The login of the AI tool it ran on (`pro`); nil for the tool's default.
    public var account: String?
    public var model: String?
    public var effort: String?
    /// How long it ran, once it ended.
    public var durationMs: Int?
    /// What shows under the header when it is open: the main rows and the subagents (read-only, the resume above covers the whole
    /// session) in the order the events happened.
    public var body: TranscriptBody = .items([])
}

// MARK: result

/// The closing row of a session: how it ended and what the agent says it checked. Its summary is the engine's hand-off to the
/// next agent, not for the person: the agent's own last message already tells it.
public struct ResultCard: Equatable {
    public struct CI: Equatable {
        /// "passed" or "absent" (no CI to check); a value added later still shows.
        public var verdict: String
        public var evidence: String
    }

    public enum Tone: Equatable { case good, warning, stop }

    /// "Completed", "Changes requested", "Needs a human".
    public var outcome: String
    public var tone: Tone
    /// What the agent says it checked; nil when the result has no verification.
    public var ci: CI?
    /// Why the agent stopped; nil unless the outcome is needs_human.
    public var reason: String?

    /// Whether the row opens: only the evidence is behind it, the reason of a stop is always drawn.
    public var hasDetails: Bool { ci != nil }
}

public func resultCard(_ result: SessionResult?, bundle: Bundle? = nil, locale: Locale = .current) -> ResultCard? {
    guard let result else { return nil }
    let outcome: (String, ResultCard.Tone) = switch result.outcome {
    case "completed": (Copy.sessionOutcomeCompleted(bundle: bundle, locale: locale), .good)
    case "changes_requested": (Copy.sessionOutcomeChangesRequested(bundle: bundle, locale: locale), .warning)
    case "needs_human": (Copy.sessionOutcomeNeedsHuman(bundle: bundle, locale: locale), .stop)
    default: (capitalizingFirst(result.outcome.replacingOccurrences(of: "_", with: " ")), .warning) // a value added later still shows
    }
    return ResultCard(
        outcome: outcome.0, tone: outcome.1,
        ci: result.verification.map { ResultCard.CI(verdict: $0.ci, evidence: $0.evidence) },
        reason: result.outcome == "needs_human" ? result.reason : nil
    )
}

/// "CI passed", "No CI".
public func ciVerdictText(_ word: String, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    switch word {
    case "passed": Copy.sessionCiPassed(bundle: bundle, locale: locale)
    case "absent": Copy.sessionCiAbsent(bundle: bundle, locale: locale)
    default: Copy.sessionCiOther(verdict: word, bundle: bundle, locale: locale) // a value added later still shows
    }
}

// MARK: earlier sessions

/// The sessions kept in view, the newest ones; the rest wait behind one row.
public let sessionsShown = 5

/// The sessions behind the row: how many, which roles and how long they ran.
public struct EarlierSessions: Equatable {
    /// Oldest first, as in the list.
    public var sections: [SessionSection]

    /// "3 earlier sessions".
    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String { Copy.sessionEarlierTitle(count: sections.count, bundle: bundle, locale: locale) }

    /// "Builder, Reviewer, Fixer · 45m": each role once, in the order they came, and the time they ran together (left out when none is known).
    public var detail: String {
        var roles: [String] = []
        for section in sections where roles.contains(section.role) == false { roles.append(section.role) }
        let total = sections.compactMap(\.durationMs).reduce(0, +)
        return (roles.isEmpty ? [] : [roles.joined(separator: ", ")] + (total > 0 ? [formatDuration(total)] : [])).joined(separator: " · ")
    }

    public func label(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        [title(bundle: bundle, locale: locale), detail].filter { $0.isEmpty == false }.joined(separator: ", ")
    }
}

/// Above `sessionsShown` sessions the oldest ones go behind one row: `earlier` is nil while all of them fit.
public func earlierSessions(_ sections: [SessionSection], shown: Int = sessionsShown) -> (earlier: EarlierSessions?, recent: [SessionSection]) {
    guard sections.count > shown else { return (nil, sections) }
    return (EarlierSessions(sections: Array(sections.dropLast(shown))), Array(sections.suffix(shown)))
}

public struct SessionList: Equatable {
    /// Whether the `sessions` reply has arrived: until it does the tab is loading, not empty.
    public var loaded: Bool
    /// Every session, oldest first: the log reads top to bottom as it happened, and the last one is what is happening now.
    public var sections: [SessionSection]
}

/// "Builder", "Reviewer", "Fixer": what the engine's stage is for the person; a stage added later still shows, by its own name.
private func stageRole(_ stage: String, bundle: Bundle?, locale: Locale) -> String {
    switch stage {
    case "ship": Copy.sessionRoleShip(bundle: bundle, locale: locale)
    case "review": Copy.sessionRoleReview(bundle: bundle, locale: locale)
    case "fix": Copy.sessionRoleFix(bundle: bundle, locale: locale)
    default: capitalizingFirst(stage)
    }
}

/// "Ship", "Review", "Fix": where a session without a round is.
private func stagePlace(_ stage: String, bundle: Bundle?, locale: Locale) -> String {
    switch stage {
    case "ship": Copy.sessionPlaceShip(bundle: bundle, locale: locale)
    case "review": Copy.sessionPlaceReview(bundle: bundle, locale: locale)
    case "fix": Copy.sessionPlaceFix(bundle: bundle, locale: locale)
    default: capitalizingFirst(stage)
    }
}

/// Anything but running and finished is a session that stopped before it was done (failed, timed_out, interrupted, invalid_result).
func sessionState(_ status: String) -> SessionSection.State {
    switch status {
    case "running": .running
    case "finished": .done
    default: .stopped
    }
}

/// The reply is newest first; the list is the other way round, like a chat. `transcripts` holds the events fetched so far, by execution id.
/// `resumable` is false for an epic that ended: its sessions are over and Continue in Terminal is not offered. Given `folds`,
/// only the sessions that are open get their body built: a folded one is not drawn, and building every transcript at every update
/// (once a second, with the clock) is what made an epic with many sessions slow.
public func sessionList(
    _ reply: SessionsReply?, transcripts: [String: Transcript] = [:], slices: [EpicReply.Slice] = [],
    now: Int = Int(Date().timeIntervalSince1970 * 1000), time: TimeFormat = .stored(), resumable: Bool = true,
    folds: SessionFolds? = nil, bundle: Bundle? = nil, locale: Locale = .current
) -> SessionList {
    let all = reply?.sessions ?? []
    let built = all.enumerated().map { index, session -> SessionSection in
        let state = sessionState(session.status)
        let transcript = transcripts[session.executionId]
        let label: String?
        switch state {
        case .running:
            label = Copy.sessionSince(time: clockTime(session.startedAt, time: time), bundle: bundle, locale: locale)
        case .done: label = session.finishedAt.map { formatDuration($0 - session.startedAt) }
        case .stopped: label = nil
        }
        let agent = agentName(session.agent.harness)
        var section = SessionSection(
            id: session.executionId,
            state: state,
            agent: agent,
            initial: session.agent.harness == "codex" ? "X" : agent.prefix(1).uppercased(),
            role: stageRole(session.stage, bundle: bundle, locale: locale),
            place: session.round.map { Copy.sessionPlaceRound(round: String($0), bundle: bundle, locale: locale) } ?? stagePlace(session.stage, bundle: bundle, locale: locale),
            counts: transcript.flatMap { $0.structured ? sessionCounts($0.events) : nil },
            timeLabel: label,
            openByDefault: index == 0,
            resume: state == .running || resumable == false ? nil : session.resume,
            result: resultCard(session.result, bundle: bundle, locale: locale),
            failure: session.failure.map { $0.detail.isEmpty ? $0.kind : "\($0.kind): \($0.detail)" },
            engineRole: session.role,
            stage: session.stage,
            round: session.round,
            profile: session.profile,
            account: session.agent.provider,
            model: session.agent.model,
            durationMs: session.finishedAt.map { $0 - session.startedAt },
            body: .items([])
        )
        if folds?.isOpen(section) ?? true {
            section.body = transcriptBody(transcript, slices: slices, running: state == .running, now: now, time: time, bundle: bundle, locale: locale)
        }
        return section
    }
    return SessionList(loaded: reply != nil, sections: built.reversed())
}

/// What the poller should ask for to fill this list: the events of the open running session (live) and, once, those of the
/// finished ones shown (for their counts), and those of the older ones while their row is open.
public func epicFocus(_ epic: EpicRef, running: Bool, data: EpicData?, folds: SessionFolds, filesShown: Bool) -> EpicFocus {
    let list = sessionList(data?.sessions)
    return EpicFocus(
        epic: epic,
        epicRunning: running,
        // the tab's count shows before the tab is opened, so the files are asked until a reply with its totals came (an epic with no worktree yet has none); after that, only while the tab is on screen
        filesTabVisible: filesShown || data?.files?.total == nil,
        transcript: list.sections.first { $0.state == .running && folds.isOpen($0) }?.id,
        // newest first: it is the one a person opens
        counting: list.sections.reversed().filter { $0.state != .running }.map(\.id)
    )
}
