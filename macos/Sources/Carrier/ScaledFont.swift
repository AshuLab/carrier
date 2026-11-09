import AppKit
import CarrierCore
import Observation
import SwiftUI

/// The text size the person chose, for the views to read while they draw: a view that sets a font through `scaled` is drawn again when
/// the size changes, so moving the slider in Settings rescales the whole interface at once.
@Observable final class TextSize {
    static let shared = TextSize()

    private(set) var percent = TypeScale.stored().percent

    private init() {
        // any change of the defaults: what the slider writes, and what Reset removes
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [self] _ in
            let stored = TypeScale.stored().percent
            if stored != percent { percent = stored }
        }
    }

    var scale: TypeScale { TypeScale(percent: percent) }
}

/// The monospace settings the person chose, for the views that draw code to read while they draw (the same way as `TextSize`).
@Observable final class MonospaceStyle {
    static let shared = MonospaceStyle()

    /// The monospaced families installed on this Mac, by name.
    static let installedFamilies: [String] = {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter { family in
            guard let traits = manager.availableMembers(ofFontFamily: family)?.first?[3] as? UInt else { return false }
            return NSFontTraitMask(rawValue: traits).contains(.fixedPitchFontMask)
        }
    }()

    private(set) var settings = stored()

    private init() {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [self] _ in
            let current = Self.stored()
            if current != settings { settings = current }
        }
    }

    private static func stored() -> MonospaceSettings { AppPreferences().monospace.resolved(installed: installedFamilies) }
}

extension MonospaceSettings {
    /// The chosen font at `base` points (a size over the default 12), scaled by the person's text size.
    func font(_ base: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let points = TextSize.shared.scale.size(base * size / Self.defaultSize)
        let own = family == Self.systemFamily ? nil : NSFont(
            descriptor: NSFontDescriptor(fontAttributes: [.family: family, .traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]]),
            size: points
        )
        let font = own ?? .monospacedSystemFont(ofSize: points, weight: weight)
        let ligature = ligatures ? kCommonLigaturesOnSelector : kCommonLigaturesOffSelector
        let feature: [NSFontDescriptor.FeatureKey: Int] = [.typeIdentifier: kLigaturesType, .selectorIdentifier: ligature]
        return NSFont(descriptor: font.fontDescriptor.addingAttributes([.featureSettings: [feature]]), size: points) ?? font
    }
}

extension NSFont {
    /// The font of code and output at `base` points, as the monospace settings and the text size make it.
    static func code(_ base: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        MonospaceStyle.shared.settings.font(base, weight: weight)
    }
}

private struct CodeFont: ViewModifier {
    let base: CGFloat
    let weight: NSFont.Weight

    func body(content: Content) -> some View {
        let mono = MonospaceStyle.shared.settings
        let font = mono.font(base, weight: weight)
        content.font(Font(font)).lineSpacing(mono.lineHeight.extraSpacing(forSize: font.pointSize))
    }
}

extension View {
    /// The font and line height of code and output at `base` points: the monospace settings, then the text size. A view that reads it
    /// is drawn again when either changes.
    func codeFont(_ base: CGFloat, weight: NSFont.Weight = .regular) -> some View { modifier(CodeFont(base: base, weight: weight)) }
}

extension Font {
    /// The system font at `base` points scaled by the person's text size; the only way a view sets a size.
    static func scaled(_ base: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(size: TextSize.shared.scale.size(base), weight: weight, design: design)
    }
}

extension NSFont {
    /// The system font at `base` points scaled by the person's text size.
    static func scaled(_ base: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: TextSize.shared.scale.size(base), weight: weight)
    }

    /// The monospaced system font at `base` points scaled by the person's text size.
    static func scaledMono(_ base: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedSystemFont(ofSize: TextSize.shared.scale.size(base), weight: weight)
    }

    // The menu bar and the menus are the system's chrome: the text size does not reach them.
    static let statusItemDigits = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
    static let menuTitle = NSFont.systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold)
}

extension ColorSchemeChoice {
    /// What `NSApp.appearance` takes: nil follows the Mac.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// The color scheme chosen in Settings, on every window of the app: set now and again whenever the defaults change.
@MainActor func followColorScheme() {
    func apply() {
        let appearance = AppPreferences().colorScheme.appearance
        if NSApp.appearance?.name != appearance?.name { NSApp.appearance = appearance }
    }
    apply()
    NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { apply() }
    }
}
