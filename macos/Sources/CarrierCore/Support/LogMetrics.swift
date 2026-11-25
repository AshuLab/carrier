import Foundation

/// The measures every row of the Agent output log shares, in points from the session card's edge (the numbers of
/// docs/research/macos-app-design/explorations/agent-output-spec.html, section 4b). A view reads them here instead of repeating them.
public enum LogMetrics {
    // columns from the leading edge
    /// The inset of every row, and so the x of the icon column.
    public static let iconColumn: CGFloat = 12
    public static let iconWidth: CGFloat = 16
    public static let gap: CGFloat = 8

    // columns from the trailing edge, reserved on every row
    public static let durationColumn: CGFloat = 44
    public static let statusColumn: CGFloat = 14
    public static let chevronColumn: CGFloat = 10

    // heights
    public static let skillRow: CGFloat = 30

    /// The chevron's turn in seconds; nil under Reduce Motion, where it does not animate. Nothing else in the log animates.
    public static func chevronTurn(reduceMotion: Bool) -> TimeInterval? { reduceMotion ? nil : 0.12 }
}
