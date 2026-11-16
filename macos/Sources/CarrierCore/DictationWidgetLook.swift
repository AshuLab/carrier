import CoreGraphics
import Foundation

// What the widget of the global dictation draws, apart from the window: its styles, its places and the look of each state. The widget reads
// `GlobalDictation.shown` and `AppPreferences.dictationWidgetStyle`, and the window is placed by `dictationWidgetOrigin`.

/// The widget's style, chosen on the Dictation page: a badge with a microphone, or a box of 2, 3 or 4 lines.
public enum DictationWidgetStyle: String, CaseIterable, Sendable {
    case pill, small, medium, large

    public var title: String { rawValue.capitalized }

    /// The box the style is; nil for the Pill, which has no text.
    public var box: DictationWidgetBox? {
        switch self {
        case .pill: nil
        case .small: DictationWidgetBox(lines: 2, width: 340, text: 12)
        case .medium: DictationWidgetBox(lines: 3, width: 420, text: 14)
        case .large: DictationWidgetBox(lines: 4, width: 540, text: 17)
        }
    }
}

/// Where the widget sits on the display of the window in front: the top centre under the menu bar, or the bottom centre above the Dock.
public enum DictationWidgetPosition: String, CaseIterable, Sendable {
    case top, bottom

    public var title: String { rawValue.capitalized }
}

/// A box of the widget: `lines` of text at `text` points, `width` points wide.
public struct DictationWidgetBox: Equatable, Sendable {
    public let lines: Int
    public let width: CGFloat
    public let text: CGFloat

    /// The lines a text that was only copied adds for its reason, which sits over the text and not in what scrolls.
    public static let reasonLines = 3

    public func lineHeight(textSize: CGFloat) -> CGFloat { textSize * 1.25 }

    /// One height per style: the lines of text, and under them the row of the time and the keys, or of the buttons, with the box's padding.
    public func height(textSize: CGFloat) -> CGFloat { (CGFloat(lines) * lineHeight(textSize: textSize)).rounded(.up) + 52 }
}

/// How a text of `textLines` sits in a box of `boxLines`: it starts at the top and fills lines down to the box's, and once it is longer the newest
/// words are on the last line and the older lines fade out at the top.
public struct DictationTextFit: Equatable, Sendable {
    public let visibleLines: Int
    public let fadesTop: Bool
}

public func dictationTextFit(textLines: Int, boxLines: Int) -> DictationTextFit {
    DictationTextFit(visibleLines: min(max(textLines, 0), boxLines), fadesTop: textLines > boxLines)
}

/// What the widget is doing, as it draws it: working is getting the model ready or transcribing, cleaning is the model of Cleanup at work, and
/// `pastedRaw` is a text pasted without the cleaning that was on.
public enum DictationWidgetState: Equatable, Sendable { case working, listening, cleaning, failed, copied, pasted, pastedRaw, cancelled }

public enum DictationWidgetIcon: Equatable, Sendable { case mic, spinner, sparkle, check, warning, xmark }

public struct DictationWidgetLook: Equatable, Sendable {
    public static let pillSize = CGSize(width: 76, height: 38)
    /// The box to draw, nil for the Pill.
    public let box: DictationWidgetBox?
    /// The Pill's icon; nil for the states that are text and buttons, which are never a Pill.
    public let icon: DictationWidgetIcon?
    /// The style is the Pill and the state needs text or a button, so it opens as the Small box until dismissed.
    public let opensAsSmall: Bool
    /// How long it stays before it goes away by itself, in seconds; 0 for a state that stays.
    public let linger: Double
    public var fades: Bool { linger > 0 }
}

public func dictationWidgetLook(_ state: DictationWidgetState, style: DictationWidgetStyle) -> DictationWidgetLook {
    let needsText = state == .failed || state == .copied
    let icon: DictationWidgetIcon? =
        switch state {
        case .working: .spinner
        case .listening: .mic
        case .cleaning: .sparkle
        case .pasted: .check
        case .pastedRaw: .warning
        case .cancelled: .xmark
        case .failed, .copied: nil
        }
    var box = style.box ?? (needsText ? DictationWidgetStyle.small.box : nil)
    if state == .copied, let base = box { box = DictationWidgetBox(lines: base.lines + DictationWidgetBox.reasonLines, width: base.width, text: base.text) }
    return DictationWidgetLook(
        box: box, icon: icon, opensAsSmall: style == .pill && needsText,
        // the warning stays longer: it holds the cause
        linger: state == .pastedRaw ? 4 : state == .pasted || state == .cancelled ? 1.2 : 0)
}

/// The bottom left of a widget of `size` in `area` (the display's visible frame, which leaves out the menu bar and the Dock; y grows upward): centred, `margin` from the edge.
public func dictationWidgetOrigin(size: CGSize, in area: CGRect, position: DictationWidgetPosition, margin: CGFloat = 24) -> CGPoint {
    CGPoint(x: area.midX - size.width / 2, y: position == .top ? area.maxY - size.height - margin : area.minY + margin)
}
