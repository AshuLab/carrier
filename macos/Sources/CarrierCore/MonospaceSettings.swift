import Foundation

/// The room between the lines of code and output: a multiple of the font's size.
public enum LineHeight: String, CaseIterable {
    case tight, normal, loose

    public var title: String { rawValue.capitalized }

    public var multiple: CGFloat {
        switch self {
        case .tight: 1.2
        case .normal: 1.45
        case .loose: 1.7
        }
    }

    /// What goes between the lines on top of the font's own: a monospaced font's line is about 1.2 times its size, so tight adds nothing.
    public func extraSpacing(forSize size: CGFloat) -> CGFloat { size * (multiple - 1.2) }
}

/// How code and output are drawn wherever the app shows them (the transcript, the tool output, the approvals, the agent output window).
public struct MonospaceSettings: Equatable {
    /// The family that stands for the system's monospaced font, the default.
    public static let systemFamily = "System"
    public static let defaultSize: CGFloat = 12
    public static let sizeRange: ClosedRange<CGFloat> = 9...20

    public var family: String
    /// Points before the type scale: the views draw their code at this size over `defaultSize` of their own.
    public var size: CGFloat
    public var lineHeight: LineHeight
    public var ligatures: Bool
    /// False keeps each line whole and scrolls sideways.
    public var wrapLongLines: Bool
    public var lineNumbers: Bool

    public init(
        family: String = systemFamily, size: CGFloat = defaultSize, lineHeight: LineHeight = .normal,
        ligatures: Bool = true, wrapLongLines: Bool = true, lineNumbers: Bool = false
    ) {
        self.family = family
        self.size = size
        self.lineHeight = lineHeight
        self.ligatures = ligatures
        self.wrapLongLines = wrapLongLines
        self.lineNumbers = lineNumbers
    }

    /// The settings as drawn: a family that is no longer installed falls back to the system's monospaced font.
    public func resolved(installed: [String]) -> MonospaceSettings {
        var settings = self
        if family != Self.systemFamily, installed.contains(family) == false { settings.family = Self.systemFamily }
        return settings
    }
}
