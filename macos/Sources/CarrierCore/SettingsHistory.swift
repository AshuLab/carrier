/// A place in Settings: a page and, for a page with screens of its own, which one (the Providers page names a provider, and an account of it,
/// in `path`). An empty path is the page's first screen.
public struct SettingsPlace: Equatable, Sendable {
    public var page: SettingsPage
    public var path: [String]

    public init(_ page: SettingsPage, path: [String] = []) {
        self.page = page
        self.path = path
    }
}

/// The places Settings has been at, so ‹ and › go back and forward as a browser's do: visiting a place from the middle drops what was ahead.
public struct SettingsHistory: Equatable, Sendable {
    public private(set) var places: [SettingsPlace]
    public private(set) var index = 0

    public init(_ page: SettingsPage = .general) { places = [SettingsPlace(page)] }

    public var current: SettingsPlace { places[index] }
    public var page: SettingsPage { current.page }
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index < places.count - 1 }

    /// Going to the place already shown adds nothing.
    public mutating func visit(_ place: SettingsPlace) {
        guard place != current else { return }
        places = Array(places[...index]) + [place]
        index += 1
    }

    public mutating func visit(_ page: SettingsPage) { visit(SettingsPlace(page)) }

    public mutating func back() { if canGoBack { index -= 1 } }
    public mutating func forward() { if canGoForward { index += 1 } }
}
