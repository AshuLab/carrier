import Foundation

/// Where a new session opens when its folder offers a worktree; a draft's own choice stays above it.
public enum WorkIn: String, CaseIterable, Sendable {
    case baseFolder, newWorktree

    public var title: String { self == .baseFolder ? "The base folder" : "A new worktree" }
}

public enum ColorSchemeChoice: String, CaseIterable {
    case system, light, dark

    public var title: String { rawValue.capitalized }
}

/// How tight the app packs its rows: the vertical padding of a sidebar row and the space between the messages of a conversation.
public enum Density: String, CaseIterable {
    case compact, comfortable

    public var title: String { rawValue.capitalized }
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

    public var title: String { rawValue.capitalized }

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

    public var title: String { rawValue.capitalized }
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

    public var title: String {
        switch self {
        case .ultraWide: "Ultra wide"
        default: rawValue.capitalized
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

    public var title: String { rawValue.capitalized }
}

/// When a message shows the time it was written.
public enum MessageTimes: String, CaseIterable {
    case never, hover, always

    public var title: String { rawValue == "hover" ? "On hover" : rawValue.capitalized }

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

    public var title: String { rawValue.capitalized }

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

    public var title: String { rawValue.capitalized }
}

/// How many lines of an output show before Show more.
public enum OutputLength: Int, CaseIterable {
    case short = 20, medium = 50, long = 100

    public var title: String { "\(rawValue) lines" }

    /// The first lines of an output and how many are left out; all of it once expanded.
    public func visible(_ lines: [String], expanded: Bool) -> (lines: [String], hidden: Int) {
        guard expanded == false, lines.count > rawValue else { return (lines, 0) }
        return (Array(lines.prefix(rawValue)), lines.count - rawValue)
    }
}
