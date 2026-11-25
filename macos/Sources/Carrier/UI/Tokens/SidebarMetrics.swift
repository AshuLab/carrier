import SwiftUI

/// What every sidebar row is laid out with. The scroll area and the foot keep `edge` on both sides, so nothing inside has a side margin
/// of its own; a row draws its fill edge to edge of that and keeps its content `inset` inside the fill. The type has four levels, one
/// for each job: a section (Home, Sessions, Carrier), a group's title, an item's title (a session, an epic) and its detail.
enum SidebarMetrics {
    static let edge: CGFloat = 8
    static let inset: CGFloat = 12
    static var section: Font { Font.scaled(16, weight: .medium) }
    static var group: Font { Font.scaled(12, weight: .semibold) }
    static var item: Font { Font.scaled(14) }
    static var detail: Font { Font.scaled(12) }
    /// Between rows: each one carries its own vertical padding.
    static let rowGap: CGFloat = 2
    /// The vertical padding of a section's row, and between an item's lines; an item's row takes its padding from the density, on all four
    /// sides when it has a project icon (the tile is as far from the left edge of its fill as from the top and bottom).
    static let sectionPadding: CGFloat = 8
    static let lineGap: CGFloat = 3
    /// Above a group's title, so it reads where a group begins; under it the first row is closer.
    static let groupTop: CGFloat = 10
}
