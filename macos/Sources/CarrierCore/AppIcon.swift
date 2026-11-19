import Foundation

// The icons of the app's own interface, by what they mean and not by how a set draws them: `IconSets.swift` says which file or symbol each is in each set
// (SF Symbols, Tabler, Lucide). An icon is added here and in all three sets; `IconsTests` fails when a set lacks one or its file.

public enum AppIcon: String, CaseIterable, Sendable {
    case arrowDown
    case arrowRight
    case arrowUpRight
    case ban
    case bell
    case brain
    case brush
    case chartBar
    case check
    case checkCircleFilled
    case chevronRight
    case circle
    case close
    case coin
    case copy
    case cpu
    case cube
    case cup
    case desktop
    case dots
    case download
    case downloadTray
    case exchange
    case exclamation
    case externalLink
    case eye
    case eyeOff
    case fileText
    case folder
    case folderPlus
    case folderQuestion
    case hash
    case help
    case history
    case inbox
    case info
    case keyboard
    case lock
    case lockOpen
    case messages
    case microphone
    case minus
    case playFilled
    case plus
    case power
    case question
    case radioOn
    case record
    case refresh
    case rotate
    case search
    case send
    case server
    case settings
    case sidebar
    case sliders
    case star
    case stethoscope
    case stopFilled
    case terminal
    case trash
    case undo
    case users
    case warningFilled
    case world

    /// An icon whose look is a solid shape (a warning, a ready mark, play, stop): a set that has it filled draws it so, and one that has not draws it as it can.
    public var isSolid: Bool { [.warningFilled, .checkCircleFilled, .playFilled, .stopFilled].contains(self) }
}
