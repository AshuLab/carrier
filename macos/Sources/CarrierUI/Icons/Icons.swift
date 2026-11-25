import AppKit
import CarrierCore
import Observation
import SwiftUI

/// The image of an icon in a set at a weight: the SVG with its stroke rewritten, as a template image so it takes the color of its text. Kept by set, icon and weight.
@MainActor public enum IconImages {
    private static var cache: [String: NSImage] = [:]

    /// nil for an SF Symbol, which `Glyph` draws as text.
    public static func image(_ icon: AppIcon, set: IconSet, weight: Double) -> NSImage? {
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

    /// The same in the set and weight it is given: what a test, or a caller that holds the appearance itself, asks for.
    public static func image(_ icon: AppIcon, set: IconSet, weight: Double, bold: Bool, pointSize: CGFloat = 24) -> NSImage {
        let weight = weight + (bold ? 0.75 : 0)
        if let image = image(icon, set: set, weight: weight) { return image }
        guard let symbol = NSImage(systemSymbolName: icon.systemSymbolName, accessibilityDescription: nil) else { return NSImage() }
        let configured = symbol.withSymbolConfiguration(.init(pointSize: pointSize * 0.9, weight: NSFont.Weight(strokeWeight: weight))) ?? symbol
        configured.isTemplate = true
        return configured
    }

    /// The image of an icon in a `Text`, `side` points square: an SVG is made that size, and a symbol, which comes at its own proportions, at that point size.
    public static func inline(_ icon: AppIcon, side: CGFloat, set: IconSet, weight: Double) -> NSImage {
        let image = self.image(icon, set: set, weight: weight, bold: false, pointSize: side)
        let own = (image.copy() as? NSImage) ?? image
        if case .svg = iconAsset(icon, in: set) { own.size = NSSize(width: side, height: side) }
        own.isTemplate = true
        return own
    }
}

extension NSImage {
    /// A template image drawn in `color` and fitted in `size` without stretching it: a text attachment or a layer gets no tint from the system.
    public func tinted(_ color: NSColor, size: NSSize = NSSize(width: 24, height: 24)) -> NSImage {
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
    public init(strokeWeight weight: Double) {
        self = [Font.Weight.thin, .light, .regular, .medium, .semibold, .bold, .heavy][IconWeight.symbolStep(weight)]
    }
}

extension NSFont.Weight {
    public init(strokeWeight weight: Double) {
        self = [NSFont.Weight.thin, .light, .regular, .medium, .semibold, .bold, .heavy][IconWeight.symbolStep(weight)]
    }
}

extension Label where Title == Text, Icon == Image {
    /// A title and an icon for what the system draws: the item of a menu and of the window's toolbar. Its image stays an SF Symbol whatever the set is (an item
    /// whose icon is a view of ours would lose it, or sit badly in the toolbar).
    public init<S: StringProtocol>(_ title: S, systemIcon: AppIcon) {
        self.init(title, systemImage: systemIcon.systemSymbolName)
    }
}

/// An icon of the interface in the set the person chose, at `size` points (scaled by the person's text size), in the color of its text. The icons the system
/// draws keep SF Symbols whatever the set is; this is for the app's own. `bold` is for a small white mark on a color (a state's check), where the weight the
/// person chose would be too thin to read: a stroke three quarters thicker.
public struct Glyph: View {
    let icon: AppIcon
    var size: CGFloat = 14
    var bold = false
    @Environment(\.textScale) private var textScale
    @Environment(\.pieceTheme) private var theme
    /// What VoiceOver says of an icon that is a state on its own (a tick that says "Pasted"); an icon beside words is decoration and says nothing.
    var label: String?

    public init(_ icon: AppIcon, size: CGFloat = 14, bold: Bool = false, label: String? = nil) {
        self.icon = icon
        self.size = size
        self.bold = bold
        self.label = label
    }

    public var body: some View {
        let side = textScale.size(size)
        let weight = theme.iconWeight + (bold ? 0.75 : 0)
        Group {
            if let image = IconImages.image(icon, set: theme.iconSet, weight: weight) {
                Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
            } else if case .symbol(let name) = iconAsset(icon, in: .sfSymbols) {
                // a symbol of the font's size draws a little bigger than the SVGs' box does
                Image(systemName: name).scaledFont(size * 0.9, weight: Font.Weight(strokeWeight: weight))
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(label == nil)
        .accessibilityLabel(label ?? "")
    }
}

extension Label where Title == Text, Icon == Glyph {
    /// A title and an icon of the interface, the way `Label(_:systemImage:)` has them.
    public init<S: StringProtocol>(_ title: S, icon: AppIcon, size: CGFloat = 14) {
        self.init { Text(title) } icon: { Glyph(icon, size: size) }
    }
}

extension View {
    /// An icon that turns while `on`, as the SF Symbols' rotate effect did: an SVG has no symbol effects of its own. None of the four moves with Reduce Motion on.
    public func glyphSpinning(_ on: Bool) -> some View { modifier(GlyphSpin(on: on)) }
    /// An icon that bounces down while `on`.
    public func glyphBouncing(_ on: Bool) -> some View { modifier(GlyphBounce(on: on)) }
    /// An icon that gives a little kick each time `trigger` changes, as the SF Symbols' bounce did.
    public func glyphKick(_ trigger: some Equatable) -> some View { modifier(GlyphKick(trigger: trigger)) }
    /// An icon that fades in and out while `on`. Only for something that lasts a moment: the animation does not stop while the window is hidden.
    public func glyphPulsing(_ on: Bool) -> some View { modifier(GlyphPulse(on: on)) }
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

