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

/// The image of an icon in a set at a weight: the SVG with its stroke rewritten, as a template image so it takes the color of its text. Kept by set, icon and weight.
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

    /// For the AppKit that draws an icon itself (an attachment, a layer): the icon in the set and at the weight now, with `bold` as `Glyph` has it. An SF
    /// Symbol comes at `pointSize` and the weight as the weight of its font, as `Glyph` draws it.
    static func image(_ icon: AppIcon, bold: Bool = false, pointSize: CGFloat = 24) -> NSImage {
        let style = IconAppearance.shared
        let weight = style.weight + (bold ? 0.75 : 0)
        if let image = image(icon, set: style.set, weight: weight) { return image }
        guard case .symbol(let name) = iconAsset(icon, in: .sfSymbols),
              let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return NSImage() }
        let configured = symbol.withSymbolConfiguration(.init(pointSize: pointSize * 0.9, weight: NSFont.Weight(strokeWeight: weight))) ?? symbol
        configured.isTemplate = true
        return configured
    }
}

extension NSImage {
    /// A template image drawn in `color` and fitted in `size` without stretching it: a text attachment or a layer gets no tint from the system.
    func tinted(_ color: NSColor, size: NSSize = NSSize(width: 24, height: 24)) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            let ratio = min(rect.width / max(self.size.width, 1), rect.height / max(self.size.height, 1))
            let fit = NSSize(width: self.size.width * ratio, height: self.size.height * ratio)
            let target = NSRect(x: rect.midX - fit.width / 2, y: rect.midY - fit.height / 2, width: fit.width, height: fit.height)
            self.draw(in: target)
            color.set()
            target.fill(using: .sourceAtop)
            return true
        }
    }
}

extension Font.Weight {
    /// The font weight an SF Symbol takes for a stroke of `weight` in the grid of the SVGs.
    init(strokeWeight weight: Double) {
        self = [Font.Weight.thin, .light, .regular, .medium, .semibold, .bold, .heavy][IconWeight.symbolStep(weight)]
    }
}

extension NSFont.Weight {
    init(strokeWeight weight: Double) {
        self = [NSFont.Weight.thin, .light, .regular, .medium, .semibold, .bold, .heavy][IconWeight.symbolStep(weight)]
    }
}

extension Label where Title == Text, Icon == Image {
    /// A title and an icon for what the system draws: the item of a menu and of the window's toolbar. Its image stays an SF Symbol whatever the set is (an item
    /// whose icon is a view of ours would lose it, or sit badly in the toolbar).
    init<S: StringProtocol>(_ title: S, systemIcon: AppIcon) {
        guard case .symbol(let name) = iconAsset(systemIcon, in: .sfSymbols) else { self.init(title, systemImage: "questionmark"); return }
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
    /// What VoiceOver says of an icon that is a state on its own (a tick that says "Pasted"); an icon beside words is decoration and says nothing.
    var label: String?

    init(_ icon: AppIcon, size: CGFloat = 14, bold: Bool = false, label: String? = nil) {
        self.icon = icon
        self.size = size
        self.bold = bold
        self.label = label
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
        .frame(width: side, height: side)
        .accessibilityHidden(label == nil)
        .accessibilityLabel(label ?? "")
    }
}

extension Label where Title == Text, Icon == Glyph {
    /// A title and an icon of the interface, the way `Label(_:systemImage:)` has them.
    init<S: StringProtocol>(_ title: S, icon: AppIcon, size: CGFloat = 14) {
        self.init { Text(title) } icon: { Glyph(icon, size: size) }
    }
}

extension View {
    /// An icon that turns while `on`, as the SF Symbols' rotate effect did: an SVG has no symbol effects of its own. None of the four moves with Reduce Motion on.
    func glyphSpinning(_ on: Bool) -> some View { modifier(GlyphSpin(on: on)) }
    /// An icon that bounces down while `on`.
    func glyphBouncing(_ on: Bool) -> some View { modifier(GlyphBounce(on: on)) }
    /// An icon that gives a little kick each time `trigger` changes, as the SF Symbols' bounce did.
    func glyphKick(_ trigger: some Equatable) -> some View { modifier(GlyphKick(trigger: trigger)) }
    /// An icon that fades in and out while `on`. Only for something that lasts a moment: the animation does not stop while the window is hidden.
    func glyphPulsing(_ on: Bool) -> some View { modifier(GlyphPulse(on: on)) }
}

private struct GlyphSpin: ViewModifier {
    let on: Bool
    @State private var turned = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let active = on && reduceMotion == false
        content.rotationEffect(.degrees(active && turned ? 360 : 0))
            .animation(active ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: turned)
            .onAppear { if active { turned = true } }
            .onChange(of: active) { _, now in turned = now }
    }
}

private struct GlyphBounce: ViewModifier {
    let on: Bool
    @State private var down = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let active = on && reduceMotion == false
        content.offset(y: active && down ? 2 : 0)
            .animation(active ? .easeInOut(duration: 0.5).repeatForever(autoreverses: true) : .default, value: down)
            .onAppear { if active { down = true } }
            .onChange(of: active) { _, now in down = now }
    }
}

private struct GlyphPulse: ViewModifier {
    let on: Bool
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let active = on && reduceMotion == false
        content.opacity(active && dim ? 0.35 : 1)
            .animation(active ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: dim)
            .onAppear { if active { dim = true } }
            .onChange(of: active) { _, now in dim = now }
    }
}

private struct GlyphKick<Trigger: Equatable>: ViewModifier {
    let trigger: Trigger
    @State private var up = false
    @State private var kicks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.scaleEffect(up ? 1.3 : 1)
            .onChange(of: trigger) { kicks += 1 }
            // one task per kick, which a quicker one replaces, so two never fight over the scale
            .task(id: kicks) {
                guard kicks > 0, reduceMotion == false else { return }
                withAnimation(.spring(duration: 0.15)) { up = true }
                try? await Task.sleep(for: .milliseconds(150))
                guard Task.isCancelled == false else { return }
                withAnimation(.spring(duration: 0.3, bounce: 0.5)) { up = false }
            }
    }
}

extension Image {
    /// An icon of the interface to put inside a `Text` (`Text("\(Image(inline: .gitBranch)) main")`), where a view cannot go: sized in points to the text, in
    /// the set and weight now, and a template, so it takes the color of the text.
    @MainActor init(inline icon: AppIcon, size: CGFloat = 11) {
        let side = TextSize.shared.scale.size(size)
        let image = IconImages.image(icon, pointSize: side)
        let own = (image.copy() as? NSImage) ?? image
        // an SVG comes at 24 points and a symbol at its own: both are made the side of the text
        if IconImages.image(icon, set: IconAppearance.shared.set, weight: IconAppearance.shared.weight) != nil { own.size = NSSize(width: side, height: side) }
        own.isTemplate = true
        self.init(nsImage: own)
    }
}
