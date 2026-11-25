import Foundation

/// Where a new session opens when its folder offers a worktree; a draft's own choice stays above it.
public enum WorkIn: String, CaseIterable, Sendable {
    case baseFolder, newWorktree

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .baseFolder: Copy.choiceWorkInBase(bundle: bundle, locale: locale)
        case .newWorktree: Copy.choiceWorkInWorktree(bundle: bundle, locale: locale)
        }
    }
}

public enum ColorSchemeChoice: String, CaseIterable {
    case system, light, dark

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .system: Copy.choiceSchemeSystem(bundle: bundle, locale: locale)
        case .light: Copy.choiceSchemeLight(bundle: bundle, locale: locale)
        case .dark: Copy.choiceSchemeDark(bundle: bundle, locale: locale)
        }
    }
}

/// How tight the app packs its rows: the vertical padding of a sidebar row and the space between the messages of a conversation.
public enum Density: String, CaseIterable {
    case compact, comfortable

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .compact: Copy.choiceDensityCompact(bundle: bundle, locale: locale)
        case .comfortable: Copy.choiceDensityComfortable(bundle: bundle, locale: locale)
        }
    }
    public var rowPadding: CGFloat { self == .compact ? 4 : 7 }
    /// A session's row in the sidebar has room around its lines: it can have three of them.
    public var sessionRowPadding: CGFloat { self == .compact ? 7 : 12 }
    public var sessionLineGap: CGFloat { self == .compact ? 3 : 5 }
}

/// The text of the messages: the chat's own size in points, which the text size of the app does not multiply.
public enum ChatText {
    public static let defaultSize: CGFloat = 13
    public static let sizeRange: ClosedRange<CGFloat> = 11...20

    /// `size` rounded to a whole point and kept inside `sizeRange`; the default for a number that is not one.
    public static func clamped(_ size: CGFloat) -> CGFloat {
        size.isNaN ? defaultSize : min(max(size.rounded(), sizeRange.lowerBound), sizeRange.upperBound)
    }
}

/// The room between the lines of a message, on top of the font's own.
public enum ChatLineSpacing: String, CaseIterable {
    case tight, normal, loose

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .tight: Copy.choiceLineTight(bundle: bundle, locale: locale)
        case .normal: Copy.choiceLineNormal(bundle: bundle, locale: locale)
        case .loose: Copy.choiceLineLoose(bundle: bundle, locale: locale)
        }
    }

    /// A share of the font's size: normal is the 4 points a 13-point message has always had.
    public func extra(forSize size: CGFloat) -> CGFloat {
        switch self {
        case .tight: size * 2 / 13
        case .normal: size * 4 / 13
        case .loose: size * 7 / 13
        }
    }

    /// What the person's bubble adds: it never had room between its lines, so Normal adds none and Loose only what it has over Normal.
    public func extraOverNormal(forSize size: CGFloat) -> CGFloat { max(0, extra(forSize: size) - Self.normal.extra(forSize: size)) }
}

/// The room between the messages of a conversation, in points.
public enum MessageSpacing: String, CaseIterable {
    case compact, comfortable, spacious

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .compact: Copy.choiceSpacingCompact(bundle: bundle, locale: locale)
        case .comfortable: Copy.choiceSpacingComfortable(bundle: bundle, locale: locale)
        case .spacious: Copy.choiceSpacingSpacious(bundle: bundle, locale: locale)
        }
    }
    public var gap: CGFloat {
        switch self {
        case .compact: 8
        case .comfortable: 12
        case .spacious: 20
        }
    }
}

/// How wide the column of a conversation is, in points: the most its messages take before they wrap.
public enum MessageWidth: String, CaseIterable {
    case narrow, medium, wide, ultraWide, widest

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .narrow: Copy.choiceWidthNarrow(bundle: bundle, locale: locale)
        case .medium: Copy.choiceWidthMedium(bundle: bundle, locale: locale)
        case .wide: Copy.choiceWidthWide(bundle: bundle, locale: locale)
        case .ultraWide: Copy.choiceWidthUltraWide(bundle: bundle, locale: locale)
        case .widest: Copy.choiceWidthWidest(bundle: bundle, locale: locale)
        }
    }

    public var points: CGFloat {
        switch self {
        case .narrow: 640
        case .medium: 760
        case .wide: 880
        case .ultraWide: 1040
        case .widest: 1280
        }
    }
}

/// What the conversation's surfaces are made of: glass blurs what is under them, flat is a quiet solid fill with a fine edge.
public enum ChatSurface: String, CaseIterable {
    case glass, flat

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .glass: Copy.choiceSurfaceGlass(bundle: bundle, locale: locale)
        case .flat: Copy.choiceSurfaceFlat(bundle: bundle, locale: locale)
        }
    }
}

/// When a message shows the time it was written.
public enum MessageTimes: String, CaseIterable {
    case never, hover, always

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .never: Copy.choiceTimesNever(bundle: bundle, locale: locale)
        case .hover: Copy.choiceTimesHover(bundle: bundle, locale: locale)
        case .always: Copy.choiceTimesAlways(bundle: bundle, locale: locale)
        }
    }

    /// Whether the time shows, given whether the pointer is over the message.
    public func shows(hovering: Bool) -> Bool { self == .always || (self == .hover && hovering) }
}

/// The key that sends a message: Return, or ⌘Return. Shift+Return makes a new line whichever is chosen.
public enum SendKey: String, CaseIterable {
    case `return`, commandReturn

    /// Whether Return pressed with these modifiers sends; if not, it makes a new line.
    public func sends(command: Bool, shift: Bool) -> Bool {
        guard shift == false else { return false }
        return self == .commandReturn ? command : command == false
    }
}

/// What sending does while the agent answers: hold the message until the turn ends, or stop the turn and send it.
public enum WhileWorking: String, CaseIterable {
    case queue, interrupt
}

/// What the agent's tools show in a conversation: nothing, each run folded, or every call open.
public enum ToolOutputMode: String, CaseIterable {
    case hidden, collapsed, expanded

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .hidden: Copy.choiceToolsHidden(bundle: bundle, locale: locale)
        case .collapsed: Copy.choiceToolsCollapsed(bundle: bundle, locale: locale)
        case .expanded: Copy.choiceToolsExpanded(bundle: bundle, locale: locale)
        }
    }

    /// Whether a run or a call opens by itself: every one when expanded, and the ones that failed while the person wants that; never hidden.
    public func opens(failed: Bool, opensFailed: Bool) -> Bool {
        switch self {
        case .hidden: false
        case .collapsed: failed && opensFailed
        case .expanded: true
        }
    }
}

/// How an edit's diff reads in a conversation.
public enum DiffStyle: String, CaseIterable {
    case unified, split

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .unified: Copy.choiceDiffUnified(bundle: bundle, locale: locale)
        case .split: Copy.choiceDiffSplit(bundle: bundle, locale: locale)
        }
    }
}

/// How many lines of an output show before Show more.
public enum OutputLength: Int, CaseIterable {
    case short = 20, medium = 50, long = 100

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String { Copy.choiceOutputLines(lines: rawValue, bundle: bundle, locale: locale) }

    /// The first lines of an output and how many are left out; all of it once expanded.
    public func visible(_ lines: [String], expanded: Bool) -> (lines: [String], hidden: Int) {
        guard expanded == false, lines.count > rawValue else { return (lines, 0) }
        return (Array(lines.prefix(rawValue)), lines.count - rawValue)
    }
}
