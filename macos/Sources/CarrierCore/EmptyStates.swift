// The nine places that can have nothing to show, with their SF Symbol, title and one line
// (docs/specs/macos-app-redesign.md, story 24; the wording is the mockup's gallery).

public enum EmptyState: CaseIterable {
    case reviewNotStarted, noFilesChanged, noSlices, waitingForSlot, nothingWaiting, nothingNeedsYou, idle, nothingToTest, noActivity

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
        }
    }
}
