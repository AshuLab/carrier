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

    /// For the AppKit that draws an icon itself (an attachment, a layer): the icon in the set and at the weight now, with `bold` as `Glyph` has it.
    static func image(_ icon: AppIcon, bold: Bool = false) -> NSImage {
        let style = IconAppearance.shared
        if let image = image(icon, set: style.set, weight: style.weight + (bold ? 0.75 : 0)) { return image }
        guard case .symbol(let name) = iconAsset(icon, in: .sfSymbols) else { return NSImage() }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
}

extension NSImage {
    /// A template image drawn in `color`: a text attachment or a layer gets no tint from the system.
    func tinted(_ color: NSColor, size: NSSize = NSSize(width: 24, height: 24)) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
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

extension Label where Title == Text, Icon == Image {
    /// A title and an icon for the item of a menu: the system draws a menu's images, so they stay SF Symbols whatever the set is (an item whose icon is a
    /// view of ours would lose it).
    init<S: StringProtocol>(_ title: S, menuIcon: AppIcon) {
        guard case .symbol(let name) = iconAsset(menuIcon, in: .sfSymbols) else { self.init(title, systemImage: "questionmark"); return }
        self.init(title, systemImage: name)
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

extension View {
    /// An icon that turns while `on`, as the SF Symbols' rotate effect did: a SVG has no symbol effects of its own.
    func glyphSpinning(_ on: Bool) -> some View { modifier(GlyphSpin(on: on)) }
    /// An icon that bounces down while `on`.
    func glyphBouncing(_ on: Bool) -> some View { modifier(GlyphBounce(on: on)) }
    /// An icon that gives a little kick each time `trigger` changes, as the SF Symbols' bounce did.
    func glyphKick(_ trigger: some Equatable) -> some View { modifier(GlyphKick(trigger: trigger)) }
    /// An icon that fades in and out while `on`.
    func glyphPulsing(_ on: Bool) -> some View { modifier(GlyphPulse(on: on)) }
}

private struct GlyphSpin: ViewModifier {
    let on: Bool
    @State private var turned = false

    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(on && turned ? 360 : 0))
            .animation(on ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: turned)
            .onAppear { if on { turned = true } }
            .onChange(of: on) { _, now in turned = now }
    }
}

private struct GlyphBounce: ViewModifier {
    let on: Bool
    @State private var down = false

    func body(content: Content) -> some View {
        content.offset(y: on && down ? 2 : 0)
            .animation(on ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true) : .default, value: down)
            .onAppear { if on { down = true } }
            .onChange(of: on) { _, now in down = now }
    }
}

private struct GlyphPulse: ViewModifier {
    let on: Bool
    @State private var dim = false

    func body(content: Content) -> some View {
        content.opacity(on && dim ? 0.35 : 1)
            .animation(on ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: dim)
            .onAppear { if on { dim = true } }
            .onChange(of: on) { _, now in dim = now }
    }
}

private struct GlyphKick<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    @State private var up = false

    func body(content: Content) -> some View {
        content.scaleEffect(up ? 1.3 : 1)
            .onChange(of: trigger) {
                withAnimation(.spring(duration: 0.15)) { up = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation(.spring(duration: 0.3, bounce: 0.5)) { up = false }
                }
            }
    }
}

extension Image {
    /// An icon of the interface to put inside a `Text` (`Text("\(Image(inline: .gitBranch)) main")`), where a view cannot go: sized in points to the text, in
    /// the set and weight now, and a template, so it takes the color of the text.
    @MainActor init(inline icon: AppIcon, size: CGFloat = 11) {
        let side = TextSize.shared.scale.size(size)
        let style = IconAppearance.shared
        if let image = IconImages.image(icon, set: style.set, weight: style.weight), let own = image.copy() as? NSImage {
            own.size = NSSize(width: side, height: side)
            own.isTemplate = true
            self.init(nsImage: own)
            return
        }
        guard case .symbol(let name) = iconAsset(icon, in: .sfSymbols) else { self.init(nsImage: NSImage()); return }
        self.init(systemName: name)
    }
}
