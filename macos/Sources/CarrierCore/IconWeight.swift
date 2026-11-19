import Foundation

/// How thick the stroke of the outline icons is, in the 24-unit grid the SVGs are drawn on: both bundled sets draw them at 2, the app's default is 1.5, and the
/// person moves it in Appearance. It is read out of the SVG's own `stroke-width`, so no icon is drawn twice; the SF Symbols take it as the weight of their font.
public enum IconWeight {
    public static let key = "appearance.iconWeight"
    public static let defaultWeight = 1.5
    public static let range = 1.0...2.5
    public static let step = 0.25

    /// The saved weight, kept inside `range`; the default while none was saved.
    public static func stored(in defaults: UserDefaults = .standard) -> Double {
        clamped(defaults.object(forKey: key) as? Double ?? defaultWeight)
    }

    public static func clamped(_ weight: Double) -> Double { min(max(weight, range.lowerBound), range.upperBound) }

    /// The SVG text with the stroke of its outline at `weight`, and, with `fill`, the outline filled (the shape is drawn solid, its strokes in the same color).
    /// A file that is already filled has no `stroke-width` of 2 and comes back as it was.
    public static func svg(_ text: String, weight: Double, fill: Bool = false) -> String {
        let stroked = text.replacingOccurrences(of: "stroke-width=\"2\"", with: "stroke-width=\"\(clamped(weight))\"")
        guard fill, let none = stroked.range(of: "fill=\"none\"") else { return stroked }
        return stroked.replacingCharacters(in: none, with: "fill=\"currentColor\"")
    }
}
