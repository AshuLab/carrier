import Foundation

// The sixteen places that can have nothing to show, with their SF Symbol, title and one line
// (docs/specs/macos-app-redesign.md, story 24; the wording is the mockup's gallery).

public enum EmptyState: CaseIterable {
    case reviewNotStarted, noFilesChanged, noSlices, waitingForSlot, nothingWaiting, nothingNeedsYou, idle, nothingToTest, noActivity
    case welcome, noSessions, noSessionsMatch, nothingArchived, noResults, noEpics, noTerminals

    public var icon: AppIcon {
        switch self {
        case .reviewNotStarted: .history
        case .noFilesChanged: .fileText
        case .noSlices: .stack
        case .waitingForSlot: .message
        case .nothingWaiting: .inbox
        case .nothingNeedsYou: .checkCircle
        case .idle: .pause
        case .nothingToTest: .folder
        case .noActivity: .messageDots
        case .welcome: .home
        case .noSessions: .messages
        case .noSessionsMatch: .search
        case .nothingArchived: .archive
        // the struck magnifier
        case .noResults: .searchOff
        case .noEpics: .send
        case .noTerminals: .terminal
        }
    }

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .reviewNotStarted: Copy.emptyReviewNotStartedTitle(bundle: bundle, locale: locale)
        case .noFilesChanged: Copy.emptyNoFilesChangedTitle(bundle: bundle, locale: locale)
        case .noSlices: Copy.emptyNoSlicesTitle(bundle: bundle, locale: locale)
        case .waitingForSlot: Copy.emptyWaitingForSlotTitle(bundle: bundle, locale: locale)
        case .nothingWaiting: Copy.emptyNothingWaitingTitle(bundle: bundle, locale: locale)
        case .nothingNeedsYou: Copy.emptyNothingNeedsYouTitle(bundle: bundle, locale: locale)
        case .idle: Copy.emptyIdleTitle(bundle: bundle, locale: locale)
        case .nothingToTest: Copy.emptyNothingToTestTitle(bundle: bundle, locale: locale)
        case .noActivity: Copy.emptyNoActivityTitle(bundle: bundle, locale: locale)
        case .welcome: Copy.emptyWelcomeTitle(bundle: bundle, locale: locale)
        case .noSessions: Copy.emptyNoSessionsTitle(bundle: bundle, locale: locale)
        case .noSessionsMatch: Copy.emptyNoSessionsMatchTitle(bundle: bundle, locale: locale)
        case .nothingArchived: Copy.emptyNothingArchivedTitle(bundle: bundle, locale: locale)
        case .noResults: Copy.emptyNoResultsTitle(bundle: bundle, locale: locale)
        case .noEpics: Copy.emptyNoEpicsTitle(bundle: bundle, locale: locale)
        case .noTerminals: Copy.emptyNoTerminalsTitle(bundle: bundle, locale: locale)
        }
    }

    public func line(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .reviewNotStarted: Copy.emptyReviewNotStartedLine(bundle: bundle, locale: locale)
        case .noFilesChanged: Copy.emptyNoFilesChangedLine(bundle: bundle, locale: locale)
        case .noSlices: Copy.emptyNoSlicesLine(bundle: bundle, locale: locale)
        case .waitingForSlot: Copy.emptyWaitingForSlotLine(bundle: bundle, locale: locale)
        case .nothingWaiting: Copy.emptyNothingWaitingLine(bundle: bundle, locale: locale)
        case .nothingNeedsYou: Copy.emptyNothingNeedsYouLine(bundle: bundle, locale: locale)
        case .idle: Copy.emptyIdleLine(bundle: bundle, locale: locale)
        case .nothingToTest: Copy.emptyNothingToTestLine(bundle: bundle, locale: locale)
        case .noActivity: Copy.emptyNoActivityLine(bundle: bundle, locale: locale)
        case .welcome: Copy.emptyWelcomeLine(bundle: bundle, locale: locale)
        case .noSessions: Copy.emptyNoSessionsLine(bundle: bundle, locale: locale)
        case .noSessionsMatch: Copy.emptyNoSessionsMatchLine(bundle: bundle, locale: locale)
        case .nothingArchived: Copy.emptyNothingArchivedLine(bundle: bundle, locale: locale)
        case .noResults: Copy.emptyNoResultsLine(bundle: bundle, locale: locale)
        case .noEpics: Copy.emptyNoEpicsLine(bundle: bundle, locale: locale)
        case .noTerminals: Copy.emptyNoTerminalsLine(bundle: bundle, locale: locale)
        }
    }

    /// The no-results line of a list searched for `query`, which is what it says in the sidebar.
    public static func noResultsLine(for query: String, bundle: Bundle? = nil, locale: Locale = .current) -> String {
        Copy.emptyNoResultsFor(query: query, bundle: bundle, locale: locale)
    }
}
