// The places the main window has been at, so ‹ and › go back and forward as a browser's do (the same walk as `SettingsHistory`, for the
// sidebar's selection): choosing a place from the middle drops what was ahead.

public struct SelectionHistory: Equatable {
    public private(set) var places: [Selection]
    public private(set) var index = 0

    public init(_ start: Selection = .home) { places = [start] }

    public var current: Selection { places[index] }
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index < places.count - 1 }

    /// Going to the place already shown adds nothing.
    public mutating func visit(_ place: Selection) {
        guard place != current else { return }
        places = Array(places[...index]) + [place]
        index += 1
    }

    public mutating func back() { if canGoBack { index -= 1 } }
    public mutating func forward() { if canGoForward { index += 1 } }

    /// A place that is gone (an archived or deleted session) leaves the history, and two equal places left side by side become one, so
    /// no click goes nowhere. The place shown stays; the one shown cannot be the one forgotten.
    public mutating func forget(_ place: Selection) {
        guard current != place else { return }
        var kept: [Selection] = []
        var shown = 0
        for (position, each) in places.enumerated() where each != place {
            if each != kept.last { kept.append(each) }
            if position == index { shown = kept.count - 1 }
        }
        places = kept
        index = shown
    }
}
