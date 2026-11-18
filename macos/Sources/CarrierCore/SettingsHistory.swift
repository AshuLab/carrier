/// The pages Settings has been on, so ‹ and › go back and forward as a browser's do: visiting a page from the middle drops what was ahead.
public struct SettingsHistory: Equatable, Sendable {
    public private(set) var pages: [SettingsPage]
    public private(set) var index = 0

    public init(_ page: SettingsPage = .general) { pages = [page] }

    public var current: SettingsPage { pages[index] }
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index < pages.count - 1 }

    /// Going to the page already shown adds nothing.
    public mutating func visit(_ page: SettingsPage) {
        guard page != current else { return }
        pages = Array(pages[...index]) + [page]
        index += 1
    }

    public mutating func back() { if canGoBack { index -= 1 } }
    public mutating func forward() { if canGoForward { index += 1 } }
}
