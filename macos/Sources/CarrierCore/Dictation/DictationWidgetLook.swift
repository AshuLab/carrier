import CoreGraphics
import Foundation

// What the widget of the global dictation draws, apart from the window: its styles, its places and the look of each state. The widget reads
// `GlobalDictation.shown`, `AppPreferences.dictationWidgetStyle`, its `dictationWidgetPreview` and its theme, and the window is placed by
// `dictationWidgetOrigin`, at the place the person chose or the spot they dragged it to.

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

/// What the widget is made of, chosen on the Dictation page: the app's accent as glass (the way it always was), a solid black, dark glass, the system's own
/// glass with no tint, or the colours of the listening line (the accent and its neighbouring hues) as glass.
public enum DictationWidgetTheme: String, CaseIterable, Sendable {
    case accent, black, glassDark, clear, glow

    public var title: String {
        switch self {
        case .accent: "Default"
        case .black: "Black"
        case .glassDark: "Dark glass"
        case .clear: "Clear glass"
        case .glow: "Theme glow"
        }
    }

    /// The appearance its text is drawn in whatever the app's is, so it reads over its own colour; nil follows the app's (the clear glass takes the system's).
    public var appearance: DictationWidgetAppearance? {
        switch self {
        case .accent, .clear: nil
        case .black, .glassDark, .glow: .dark
        }
    }
}

public enum DictationWidgetAppearance: Sendable { case light, dark }

/// Where the person left the widget by dragging it: its centre as a share of the display's visible frame across (0 left, 1 right), and the edge it hangs
/// from (the nearer one, so a box that grows opens away from it) with the gap in points. Sizes change with the state, the display with the window in front,
/// so a point of the screen would not hold; this does.
public struct DictationWidgetSpot: Equatable, Sendable {
    public let x: Double
    public let fromTop: Bool
    public let gap: Double

    public init?(x: Double, fromTop: Bool, gap: Double) {
        guard x.isFinite, gap.isFinite, (0...1).contains(x), gap >= 0 else { return nil }
        self.x = x
        self.fromTop = fromTop
        self.gap = gap
    }

    /// Where `frame` (the widget's box, without its glow) sits in `area`, clamped into it.
    public init(frame: CGRect, in area: CGRect) {
        let across = area.width > 0 ? Double((frame.midX - area.minX) / area.width) : 0.5
        let top = frame.midY >= area.midY
        self.x = min(max(across, 0), 1)
        self.fromTop = top
        self.gap = max(0, Double(top ? area.maxY - frame.maxY : frame.minY - area.minY))
    }

    /// "0.5,bottom,24": what is stored.
    public var text: String { "\(x),\(fromTop ? "top" : "bottom"),\(gap)" }

    public init?(text: String) {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 3, let x = Double(parts[0]), let gap = Double(parts[2]), parts[1] == "top" || parts[1] == "bottom" else { return nil }
        self.init(x: x, fromTop: parts[1] == "top", gap: gap)
    }
}

/// A box of the widget: `lines` of text at `text` points, `width` points wide.
public struct DictationWidgetBox: Equatable, Sendable {
    public let lines: Int
    public let width: CGFloat
    public let text: CGFloat

    /// The lines a text that was only copied adds for its reason, which sits over the text and not in what scrolls.
    public static let reasonLines = 3

    /// A box of no lines is the live text turned off: the same box, with the time and the keys and no words.
    public var showsText: Bool { lines > 0 }

    public func lineHeight(textSize: CGFloat) -> CGFloat { textSize * 1.25 }

    /// One height per style: the lines of text, and under them the row of the time and the keys, or of the buttons, with the box's padding.
    public func height(textSize: CGFloat) -> CGFloat { (CGFloat(lines) * lineHeight(textSize: textSize)).rounded(.up) + 52 }
}

/// The notices over a text that was only copied: why it was not pasted, and why it was not cleaned when Cleanup was on. The box is as tall as they
/// are, for the widget lays them out where it sizes itself (`reasonLines` is what a box allows before it grows for them).
public func dictationKeptNotices(reason: PasteReason, notCleaned: String?) -> [String] {
    ["\(reason.explanation) It is on the clipboard."] + (notCleaned.map { ["It was not cleaned: \($0)"] } ?? [])
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

/// With `livePreview` off the box has no lines of text (the time and the keys stay), except in the states that are text: a failure's cause and a copied text.
public func dictationWidgetLook(_ state: DictationWidgetState, style: DictationWidgetStyle, livePreview: Bool = true) -> DictationWidgetLook {
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
    if livePreview == false, needsText == false, let base = box { box = DictationWidgetBox(lines: 0, width: base.width, text: base.text) }
    return DictationWidgetLook(
        box: box, icon: icon, opensAsSmall: style == .pill && needsText,
        // the warning stays longer: it holds the cause
        linger: state == .pastedRaw ? 4 : state == .pasted || state == .cancelled ? 1.2 : 0)
}

/// The bottom left of a widget of `size` in `area` (the display's visible frame, which leaves out the menu bar and the Dock; y grows upward): centred, `margin` from the edge,
/// or, with a `spot` the person dragged it to, there, never out of `area`.
public func dictationWidgetOrigin(
    size: CGSize, in area: CGRect, position: DictationWidgetPosition, margin: CGFloat = 24, spot: DictationWidgetSpot? = nil
) -> CGPoint {
    guard let spot else {
        return CGPoint(x: area.midX - size.width / 2, y: position == .top ? area.maxY - size.height - margin : area.minY + margin)
    }
    let x = area.minX + CGFloat(spot.x) * area.width - size.width / 2
    let y = spot.fromTop ? area.maxY - CGFloat(spot.gap) - size.height : area.minY + CGFloat(spot.gap)
    return CGPoint(
        x: min(max(x, area.minX), max(area.minX, area.maxX - size.width)),
        y: min(max(y, area.minY), max(area.minY, area.maxY - size.height)))
}
