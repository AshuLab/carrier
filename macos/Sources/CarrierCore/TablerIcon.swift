import Foundation

// The icons of the app's own interface: Tabler Icons (MIT), bundled as SVGs in `Resources/TablerIcons` with their licence next to them. The raw value is
// the folder and the name of the file; an icon is added here with its SVG (`SOURCE.txt` says how). What the system draws (the window's toolbar, the
// menus, the pop-ups) stays in SF Symbols. `TablerIconsTests` checks that every case has its file.

public enum TablerIcon: String, CaseIterable, Sendable {
    case arrowDown = "outline/arrow-down"
    case arrowRight = "outline/arrow-right"
    case arrowUpRight = "outline/arrow-up-right"
    case ban = "outline/ban"
    case bell = "outline/bell"
    case brain = "outline/brain"
    case brush = "outline/brush"
    case chartBar = "outline/chart-bar"
    case check = "outline/check"
    case checkCircleFilled = "filled/circle-check"
    case chevronRight = "outline/chevron-right"
    case circle = "outline/circle"
    case close = "outline/x"
    case coin = "outline/coin"
    case copy = "outline/copy"
    case cpu = "outline/cpu"
    case cube = "outline/cube"
    case cup = "outline/cup"
    case desktop = "outline/device-desktop"
    case dots = "outline/dots"
    case download = "outline/circle-arrow-down"
    case downloadTray = "outline/download"
    case exchange = "outline/arrows-exchange"
    case exclamation = "outline/exclamation-mark"
    case externalLink = "outline/external-link"
    case eye = "outline/eye"
    case eyeOff = "outline/eye-off"
    case fileText = "outline/file-text"
    case folder = "outline/folder"
    case folderPlus = "outline/folder-plus"
    case folderQuestion = "outline/folder-question"
    case hash = "outline/hash"
    case help = "outline/help-circle"
    case history = "outline/history"
    case inbox = "outline/inbox"
    case info = "outline/info-circle"
    case keyboard = "outline/keyboard"
    case lock = "outline/lock"
    case lockOpen = "outline/lock-open"
    case messages = "outline/messages"
    case microphone = "outline/microphone"
    case minus = "outline/minus"
    case playFilled = "filled/player-play"
    case plus = "outline/plus"
    case power = "outline/power"
    case question = "outline/question-mark"
    case radioOn = "outline/circle-dot"
    case record = "outline/player-record"
    case refresh = "outline/refresh"
    case rotate = "outline/rotate"
    case search = "outline/search"
    case send = "outline/send"
    case server = "outline/server"
    case settings = "outline/settings"
    case sidebar = "outline/layout-sidebar"
    case sliders = "outline/adjustments-horizontal"
    case star = "outline/star"
    case stethoscope = "outline/stethoscope"
    case stopFilled = "filled/player-stop"
    case terminal = "outline/terminal"
    case trash = "outline/trash"
    case undo = "outline/arrow-back-up"
    case users = "outline/users"
    case warningFilled = "filled/alert-triangle"
    case world = "outline/world"

    /// A filled icon has no stroke, so the weight setting does not reach it.
    public var isFilled: Bool { rawValue.hasPrefix("filled/") }

    /// The SVG inside the bundle.
    public var url: URL? { carrierResources.url(forResource: String(rawValue.split(separator: "/").last ?? ""), withExtension: "svg", subdirectory: "TablerIcons/" + (isFilled ? "filled" : "outline")) }
}

/// How thick the stroke of the outline icons is, in the 24-unit grid the SVGs are drawn on: Tabler draws them at 2, the app's default is 1.5, and the person
/// moves it in Appearance. It is read out of the SVG's own `stroke-width`, so no icon is drawn twice.
public enum IconWeight {
    public static let key = "appearance.iconWeight"
    public static let defaultWeight = 1.5
    public static let range = 1.0...2.5
    public static let step = 0.25

    /// The saved weight, kept inside `range`; the default while none was saved.
    public static func stored(in defaults: UserDefaults = .standard) -> Double {
        clamped(defaults.object(forKey: key) as? Double ?? defaultWeight)
    }

    public static func clamped(_ weight: Double) -> Double { min(max(weight, range.lowerBound), range.upperBound) }

    /// The SVG text with the stroke of its outline at `weight`; a filled icon has no stroke and comes back as it was.
    public static func svg(_ text: String, weight: Double) -> String {
        text.replacingOccurrences(of: "stroke-width=\"2\"", with: "stroke-width=\"\(clamped(weight))\"")
    }
}
