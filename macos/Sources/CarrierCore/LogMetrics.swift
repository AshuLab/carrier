import Foundation

/// The measures every row of the Agent output log shares, in points from the session card's edge (the numbers of
/// docs/research/macos-app-design/explorations/agent-output-spec.html, section 4b). A view reads them here instead of repeating them.
public enum LogMetrics {
    // columns from the leading edge
    /// The inset of every row, and so the x of the icon column.
    public static let iconColumn: CGFloat = 12
    public static let iconWidth: CGFloat = 16
    public static let gap: CGFloat = 8
    /// The x of a call's title, a skill's name, a slice's title and the detail block: icon column + icon + gap.
    public static let titleColumn: CGFloat = iconColumn + iconWidth + gap
    /// A group's children hang this far in, behind a rule under the group chevron's centre.
    public static let groupIndent: CGFloat = 18
    public static let groupRule: CGFloat = 17
    public static let groupChildIcon: CGFloat = iconColumn + groupIndent
    public static let groupChildDetail: CGFloat = groupIndent + titleColumn
    /// A slice's rows hang this far in, behind a rule under the state glyph's centre.
    public static let sliceIndent: CGFloat = 24
    public static let sliceRule: CGFloat = 19
    public static let sliceChildIcon: CGFloat = sliceIndent + iconColumn
    public static let ruleWidth: CGFloat = 1.5

    // columns from the trailing edge, reserved on every row
    public static let durationColumn: CGFloat = 44
    public static let statusColumn: CGFloat = 14
    public static let chevronColumn: CGFloat = 10

    // heights
    public static let callLine: CGFloat = 26
    public static let groupLine: CGFloat = 28
    public static let sliceLine: CGFloat = 28
    public static let skillRow: CGFloat = 28

    /// The chevron's turn in seconds; nil under Reduce Motion, where it does not animate. Nothing else in the log animates.
    public static func chevronTurn(reduceMotion: Bool) -> TimeInterval? { reduceMotion ? nil : 0.12 }
}
