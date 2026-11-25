/// What a row of a page says: its title and the line under it. The row's identifier (what the search anchors on) stays with the view that draws it.
public struct PageRowText: Equatable, Sendable {
    public let title: String
    public let detail: String

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}
