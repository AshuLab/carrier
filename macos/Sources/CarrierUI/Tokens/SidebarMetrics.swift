import SwiftUI

/// What every sidebar row is laid out with. The scroll area and the foot keep `edge` on both sides, so nothing inside has a side margin
/// of its own; a row draws its fill edge to edge of that and keeps its content `inset` inside the fill. The type has four levels, one
/// for each job: a section (Home, Sessions, Carrier), a group's title, an item's title (a session, an epic) and its detail.
public enum SidebarMetrics {
    public static let edge: CGFloat = 8
    public static let inset: CGFloat = 12
    public enum Level {
        case section, group, item, detail

        var base: CGFloat {
            switch self {
            case .section: 16
            case .group, .detail: 12
            case .item: 14
            }
        }

        var weight: Font.Weight? {
            switch self {
            case .section: .medium
            case .group: .semibold
            case .item, .detail: nil
            }
        }
    }
    /// Between rows: each one carries its own vertical padding.
    public static let rowGap: CGFloat = 2
    /// The vertical padding of a section's row, and between an item's lines; an item's row takes its padding from the density, on all four
    /// sides when it has a project icon (the tile is as far from the left edge of its fill as from the top and bottom).
    static let sectionPadding: CGFloat = 8
    public static let lineGap: CGFloat = 3
    /// Above a group's title, so it reads where a group begins; under it the first row is closer.
    public static let groupTop: CGFloat = 10
}

extension View {
    /// The type of a sidebar level (`weight` for a place that sets its own), scaled by the person's text size.
    public func sidebarFont(_ level: SidebarMetrics.Level, weight: Font.Weight? = nil) -> some View {
        scaledFont(level.base, weight: weight ?? level.weight)
    }
}
