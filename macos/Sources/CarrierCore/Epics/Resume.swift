import Foundation

// Resuming a stopped epic from its view (docs/specs/resume-a-stopped-epic.md): the card the view draws, the request that asks the
// engine and the words of each way it can fail. The app has no GitHub token (ADR 0005): the engine puts the label back.

/// What the card between an epic's title and its tabs says. The view only draws it.
public struct ResumeCard: Equatable {
    /// The reason, capitalised: "Review limit reached".
    public var title: String
    /// One line of what resuming does for this kind.
    public var words: String
    /// Orange when a person's input is needed, red when something failed.
    public var attention: Attention
    /// What the confirmation sheet says will happen.
    public var sheet: [String]
    /// False for an engine that cannot be asked: the card still gives the reason and the words.
    public var showsButton: Bool

    public init(title: String, words: String, attention: Attention, sheet: [String], showsButton: Bool) {
        (self.title, self.words, self.attention, self.sheet, self.showsButton) = (title, words, attention, sheet, showsButton)
    }
}

/// nil unless the epic is stopped in needs-human. `canResume`: the engine's hello lists `resumeEpic`.
public func resumeCard(_ epic: PanelEpic, canResume: Bool, bundle: Bundle? = nil, locale: Locale = .current) -> ResumeCard? {
    guard epic.status == .needsHuman else { return nil }
    let line = interventionLine(epic, bundle: bundle, locale: locale)
    let attention = Attention(kind: epic.needsHumanKind)
    let words: String
    switch epic.needsHumanKind {
    case "review_limit": words = Copy.epicsResumeWordsReviewLimit(count: epic.maxReviews, bundle: bundle, locale: locale)
    case "agent_needs_human": words = Copy.epicsResumeWordsAgentNeedsHuman(bundle: bundle, locale: locale)
    case "retries_exhausted", "timeout", "auth", "workspace", "pr_invalid": words = Copy.epicsResumeWordsFixCause(bundle: bundle, locale: locale)
    default: words = Copy.epicsResumeWordsOther(bundle: bundle, locale: locale)
    }
    return ResumeCard(
        title: line.prefix(1).uppercased() + line.dropFirst(), words: words, attention: attention,
        sheet: [
            Copy.epicsResumeSheetLabel(bundle: bundle, locale: locale),
            Copy.epicsResumeSheetStart(bundle: bundle, locale: locale),
            Copy.epicsResumeSheetRounds(bundle: bundle, locale: locale),
            Copy.epicsResumeSheetStops(bundle: bundle, locale: locale),
        ],
        showsButton: canResume
    )
}

/// The reasons the engine gives for refusing `resumeEpic`, by the code of its refusal.
public enum ResumeRefusal: String, CaseIterable {
    case unknownEpic = "epic.unknown"
    case notStopped = "resume.notStopped"
    case githubUnavailable = "github.unavailable"
    case didNotRestart = "resume.didNotRestart"

    func words(bundle: Bundle?, locale: Locale) -> String {
        switch self {
        case .unknownEpic: Copy.epicsResumeRefusedUnknown(bundle: bundle, locale: locale)
        case .notStopped: Copy.epicsResumeRefusedNotStopped(bundle: bundle, locale: locale)
        case .githubUnavailable: Copy.epicsResumeRefusedGithub(bundle: bundle, locale: locale)
        case .didNotRestart: Copy.epicsResumeRefusedNotRestarted(bundle: bundle, locale: locale)
        }
    }
}

public enum ResumeResult: Equatable {
    /// The epic started again.
    case resumed
    /// The engine's refusal.
    case refused(Refusal)
    /// no socket to talk to, or the connection died
    case stopped
    /// an engine that does not list `resumeEpic`
    case unsupported
}

/// Asks the engine at `socketPath`. Blocks (the engine answers when the epic has started, up to thirty seconds): call it off the
/// main thread.
public func resumeEpic(socketPath: String, repo: String, issue: Int) -> ResumeResult {
    guard let client = ControlClient.connect(path: socketPath, timeout: 45) else { return .stopped }
    defer { client.close() }
    do {
        _ = try client.hello()
        return try client.resumeEpic(repo: repo, issue: issue) ? .resumed : .unsupported
    } catch ControlError.remote(let reason) {
        return .refused(reason)
    } catch {
        return .stopped
    }
}

/// What the card says when the epic was not resumed; nil when it was.
public func resumeFailureWords(_ result: ResumeResult, bundle: Bundle? = nil, locale: Locale = .current) -> String? {
    switch result {
    case .resumed: nil
    case .refused(let refusal):
        refusal.code.flatMap(ResumeRefusal.init(rawValue:))?.words(bundle: bundle, locale: locale)
            ?? Copy.epicsResumeFailed(reason: refusal.shown(bundle: bundle, locale: locale), bundle: bundle, locale: locale)
    case .stopped: Copy.epicsResumeStopped(bundle: bundle, locale: locale)
    case .unsupported: Copy.epicsResumeUnsupported(bundle: bundle, locale: locale)
    }
}
