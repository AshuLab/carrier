// The thirteen places that can have nothing to show, with their SF Symbol, title and one line
// (docs/specs/macos-app-redesign.md, story 24; the wording is the mockup's gallery).

public enum EmptyState: CaseIterable {
    case reviewNotStarted, noFilesChanged, noSlices, waitingForSlot, nothingWaiting, nothingNeedsYou, idle, nothingToTest, noActivity
    case welcome, noSessions, noSessionsMatch, nothingArchived

    public var icon: String {
        switch self {
        case .reviewNotStarted: "clock.arrow.circlepath"
        case .noFilesChanged: "doc.text"
        case .noSlices: "square.stack.3d.up"
        case .waitingForSlot: "bubble.left"
        case .nothingWaiting: "tray"
        case .nothingNeedsYou: "checkmark.circle"
        case .idle: "pause.circle"
        case .nothingToTest: "folder"
        case .noActivity: "ellipsis.bubble"
        case .welcome: "house"
        case .noSessions: "bubble.left.and.bubble.right"
        case .noSessionsMatch: "magnifyingglass"
        case .nothingArchived: "archivebox"
        }
    }

    public var title: String {
        switch self {
        case .reviewNotStarted: "Review has not started"
        case .noFilesChanged: "No files changed yet"
        case .noSlices: "No slices yet"
        case .waitingForSlot: "Waiting for a free slot"
        case .nothingWaiting: "Nothing waiting"
        case .nothingNeedsYou: "Nothing needs you"
        case .idle: "Carrier is idle"
        case .nothingToTest: "Nothing to test yet"
        case .noActivity: "No activity yet"
        case .welcome: "Welcome"
        case .noSessions: "No sessions yet"
        case .noSessionsMatch: "No sessions match"
        case .nothingArchived: "Nothing archived"
        }
    }

    public var line: String {
        switch self {
        case .reviewNotStarted: "It starts when every slice is merged."
        case .noFilesChanged: "They appear here as soon as an agent edits one."
        case .noSlices: "Carrier splits the epic into slices before it starts shipping."
        case .waitingForSlot: "No agent has started. It begins when a slot is free."
        case .nothingWaiting: "Epics marked solve:epic:ready show up here."
        case .nothingNeedsYou: "Carrier will tell you when something does."
        case .idle: "Mark an epic solve:epic:ready in a watched repo to start one."
        case .nothingToTest: "Finished epics wait here for you to try them."
        case .noActivity: "What the agent does shows up here as it works."
        case .welcome: "Pick Sessions or Carrier in the sidebar."
        case .noSessions: "Sessions you start are listed here."
        case .noSessionsMatch: "Nothing fits what you searched or filtered."
        case .nothingArchived: "Archived sessions are kept here."
        }
    }
}
