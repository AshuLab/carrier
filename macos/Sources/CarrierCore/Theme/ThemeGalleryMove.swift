import Foundation

/// One cell of the theme gallery: a theme drawn with the name it goes by. The gallery of the app gives every theme its own name; the terminal's
/// first cell is the app's theme drawn with the words "Same as the app".
public struct ThemeCell: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let theme: Theme

    public init(id: String, title: String, theme: Theme) {
        self.id = id
        self.title = title
        self.theme = theme
    }
}

/// A key the gallery answers with a move of the chosen cell.
public enum ThemeGalleryKey: Sendable { case up, down, left, right }

/// The cell the gallery moves to. The cells fill three rows column by column, so cell `n` is in row `n % 3` of column `n / 3`: up and down move one
/// cell inside the column, left and right one column in the same row. Every move stops at the ends and stays where it is; right from a row that the
/// last, shorter column does not have goes to that column's last cell.
public func themeGalleryMove(from index: Int, key: ThemeGalleryKey, count: Int, rows: Int = 3) -> Int {
    guard count > 0, rows > 0, (0..<count).contains(index) else { return index }
    switch key {
    case .up: return index % rows > 0 ? index - 1 : index
    case .down: return index % rows < rows - 1 && index + 1 < count ? index + 1 : index
    case .left: return index >= rows ? index - rows : index
    case .right:
        if index + rows < count { return index + rows }
        // the next column exists but is shorter than this row: its last cell
        return index / rows < (count - 1) / rows ? count - 1 : index
    }
}
