import Foundation

/// The cells of the terminal's theme gallery and the one chosen. The first is the app's theme drawn with the words "Same as the app"; it is the
/// chosen one while the terminal has no theme of its own (nil), and the app's theme changing changes what it draws, not which is chosen.
/// A terminal theme that equals the app's is still chosen as itself: the first cell is only for nil.
public struct TerminalThemeCells: Equatable, Sendable {
    public let cells: [ThemeCell]
    public let chosen: ThemeCell.ID

    /// The id of the first cell; no theme's raw value is this, so picking it stores nothing.
    public static let sameAsAppID = "same-as-app"

    /// What the terminal stores when a cell is picked: the theme of that cell, or nil for the first one.
    public static func stored(picking id: ThemeCell.ID) -> Theme? { Theme(rawValue: id) }
}

public func terminalThemeCells(app: Theme, stored: Theme?, bundle: Bundle? = nil, locale: Locale = .current) -> TerminalThemeCells {
    let first = ThemeCell(
        id: TerminalThemeCells.sameAsAppID, title: Copy.terminalSameAsApp(theme: app.title(bundle: bundle, locale: locale), bundle: bundle, locale: locale), theme: app)
    let themes = Theme.allCases.map { ThemeCell(id: $0.rawValue, title: $0.title(bundle: bundle, locale: locale), theme: $0) }
    return TerminalThemeCells(cells: [first] + themes, chosen: stored?.rawValue ?? TerminalThemeCells.sameAsAppID)
}
