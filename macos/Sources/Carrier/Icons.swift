import AppKit
import CarrierCore
import Observation
import SwiftUI

/// The icon set and the weight of the outline icons the person chose, for the views to read while they draw: a `Glyph` is drawn again when either changes, so
/// moving the slider or choosing another set in Appearance redraws every icon at once (the same way `TextSize` does for the text).
@Observable final class IconAppearance {
    static let shared = IconAppearance()

    private(set) var set = IconSet.stored()
    private(set) var weight = IconWeight.stored()

    private init() {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [self] _ in
            let stored = IconSet.stored()
            if stored != set { set = stored }
            let storedWeight = IconWeight.stored()
            if storedWeight != weight { weight = storedWeight }
        }
    }
}

/// The image of an icon in a set at a weight: the SVG with its stroke rewritten, as a template image so it takes the color of its text. Kept by all four.
@MainActor enum IconImages {
    private static var cache: [String: NSImage] = [:]

    /// nil for an SF Symbol, which `Glyph` draws as text.
    static func image(_ icon: AppIcon, set: IconSet, weight: Double) -> NSImage? {
        let asset = iconAsset(icon, in: set)
        guard case .svg(_, _, let fill) = asset else { return nil }
        let weight = IconWeight.clamped(weight)
        let key = "\(set.rawValue)/\(icon.rawValue)@\(weight)"
        if let known = cache[key] { return known }
        let image = asset.url
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { NSImage(data: Data(IconWeight.svg($0, weight: weight, fill: fill).utf8)) } ?? NSImage()
        image.isTemplate = true
        cache[key] = image
        return image
    }

    /// For the AppKit that draws an icon itself (a menu, the menu bar): the icon in the set and at the weight now.
    static func image(_ icon: AppIcon) -> NSImage {
        let style = IconAppearance.shared
        if let image = image(icon, set: style.set, weight: style.weight) { return image }
        guard case .symbol(let name) = iconAsset(icon, in: .sfSymbols) else { return NSImage() }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
}

extension Font.Weight {
    /// The font weight an SF Symbol takes for a stroke of `weight` in the grid of the SVGs: 1.5, the app's default, is the regular one.
    init(strokeWeight weight: Double) {
        switch weight {
        case ..<1.125: self = .thin
        case ..<1.375: self = .light
        case ..<1.625: self = .regular
        case ..<1.875: self = .medium
        case ..<2.125: self = .semibold
        case ..<2.375: self = .bold
        default: self = .heavy
        }
    }
}

/// An icon of the interface in the set the person chose, at `size` points (scaled by the person's text size), in the color of its text. The icons the system
/// draws keep SF Symbols whatever the set is; this is for the app's own. `bold` is for a small white mark on a color (a state's check), where the weight the
/// person chose would be too thin to read: a stroke three quarters thicker.
struct Glyph: View {
    let icon: AppIcon
    var size: CGFloat = 14
    var bold = false

    init(_ icon: AppIcon, size: CGFloat = 14, bold: Bool = false) {
        self.icon = icon
        self.size = size
        self.bold = bold
    }

    var body: some View {
        let side = TextSize.shared.scale.size(size)
        let style = IconAppearance.shared
        let weight = style.weight + (bold ? 0.75 : 0)
        Group {
            if let image = IconImages.image(icon, set: style.set, weight: weight) {
                Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
            } else if case .symbol(let name) = iconAsset(icon, in: .sfSymbols) {
                // a symbol of the font's size draws a little bigger than the SVGs' box does
                Image(systemName: name).font(.scaled(size * 0.9, weight: Font.Weight(strokeWeight: weight)))
            }
        }
        .frame(width: side, height: side).accessibilityHidden(true)
    }
}

extension Label where Title == Text, Icon == Glyph {
    /// A title and an icon of the interface, the way `Label(_:systemImage:)` has them.
    init<S: StringProtocol>(_ title: S, icon: AppIcon, size: CGFloat = 14) {
        self.init { Text(title) } icon: { Glyph(icon, size: size) }
    }
}

/// An icon of a shared component while the app moves from SF Symbols to the interface's own icons: the symbol it had or the icon it has now. The components
/// keep both ways in until every place that draws them has moved, and then this goes.
enum IconSource {
    case symbol(String)
    case icon(AppIcon)

    @ViewBuilder func view(size: CGFloat) -> some View {
        switch self {
        case .symbol(let name): Image(systemName: name).font(.scaled(size))
        case .icon(let icon): Glyph(icon, size: size)
        }
    }
}
