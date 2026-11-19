import AppKit
import CarrierCore
import Observation
import SwiftUI

/// The weight of the outline icons the person chose, for the views to read while they draw: a `Glyph` is drawn again when it changes, so moving the slider in
/// Appearance redraws every icon at once (the same way `TextSize` does for the text).
@Observable final class IconWeightStyle {
    static let shared = IconWeightStyle()

    private(set) var weight = IconWeight.stored()

    private init() {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [self] _ in
            let stored = IconWeight.stored()
            if stored != weight { weight = stored }
        }
    }
}

/// The image of an icon at a weight: the SVG with its stroke rewritten, as a template image so it takes the color of its text. Kept by icon and weight.
@MainActor enum TablerImages {
    private static var cache: [String: NSImage] = [:]

    static func image(_ icon: TablerIcon, weight: Double) -> NSImage {
        let weight = icon.isFilled ? 0 : IconWeight.clamped(weight)
        let key = "\(icon.rawValue)@\(weight)"
        if let known = cache[key] { return known }
        let image = icon.url
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { NSImage(data: Data(IconWeight.svg($0, weight: weight).utf8)) } ?? NSImage()
        image.isTemplate = true
        cache[key] = image
        return image
    }

    /// For the AppKit that draws an icon itself (a menu, the menu bar): the same image, at the weight now.
    static func image(_ icon: TablerIcon) -> NSImage { image(icon, weight: IconWeightStyle.shared.weight) }
}

/// An icon of the interface: a Tabler icon at `size` points (scaled by the person's text size), in the color of its text. The icons the system draws keep
/// SF Symbols; this is for the app's own. `bold` is for a small white mark on a color (a state's check), where the weight the person chose would be too
/// thin to read: a stroke three quarters thicker.
struct Glyph: View {
    let icon: TablerIcon
    var size: CGFloat = 14
    var bold = false

    init(_ icon: TablerIcon, size: CGFloat = 14, bold: Bool = false) {
        self.icon = icon
        self.size = size
        self.bold = bold
    }

    var body: some View {
        let side = TextSize.shared.scale.size(size)
        Image(nsImage: TablerImages.image(icon, weight: IconWeightStyle.shared.weight + (bold ? 0.75 : 0)))
            .renderingMode(.template).resizable().scaledToFit().frame(width: side, height: side).accessibilityHidden(true)
    }
}

extension Label where Title == Text, Icon == Glyph {
    /// A title and an icon of the interface, the way `Label(_:systemImage:)` has them.
    init<S: StringProtocol>(_ title: S, icon: TablerIcon, size: CGFloat = 14) {
        self.init { Text(title) } icon: { Glyph(icon, size: size) }
    }
}

/// An icon of a shared component while the app moves from SF Symbols to Tabler: the symbol it had or the icon it has now. The components keep both
/// ways in until every place that draws them has moved, and then this goes.
enum IconSource {
    case symbol(String)
    case tabler(TablerIcon)

    @ViewBuilder func view(size: CGFloat) -> some View {
        switch self {
        case .symbol(let name): Image(systemName: name).font(.scaled(size))
        case .tabler(let icon): Glyph(icon, size: size)
        }
    }
}
