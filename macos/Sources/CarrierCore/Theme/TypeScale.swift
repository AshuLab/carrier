import Foundation

/// The one scale every interface size goes through: a base size in points becomes the size the person's text size asks for.
public struct TypeScale: Equatable {
    public static let range = 90...130
    public static let percentKey = "appearance.textSize"

    /// The text size in percent, kept inside `range`.
    public var percent: Int { didSet { percent = Self.clamped(percent) } }

    public init(percent: Int = 100) { self.percent = Self.clamped(percent) }

    /// The saved text size; 100 while none was saved.
    public static func stored(in defaults: UserDefaults = .standard) -> TypeScale {
        TypeScale(percent: defaults.object(forKey: percentKey) as? Int ?? 100)
    }

    /// `base` scaled by the percent, rounded to the nearest half point.
    public func size(_ base: CGFloat) -> CGFloat { (base * CGFloat(percent) / 100 * 2).rounded() / 2 }

    private static func clamped(_ percent: Int) -> Int { min(max(percent, range.lowerBound), range.upperBound) }
}
