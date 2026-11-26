import Foundation

/// A color the theme hands out: components from 0 to 1, so the value is pure and the app turns it into a `Color`.
public struct RGBA: Equatable, Sendable {
    public var red: Double, green: Double, blue: Double, alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    public init(hex: UInt32, alpha: Double = 1) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }

    public static let clear = RGBA(red: 0, green: 0, blue: 0, alpha: 0)

    /// `top` laid over `self`.
    func covered(by top: RGBA) -> RGBA {
        let alpha = top.alpha + self.alpha * (1 - top.alpha)
        guard alpha > 0 else { return .clear }
        func mix(_ over: Double, _ under: Double) -> Double { (over * top.alpha + under * self.alpha * (1 - top.alpha)) / alpha }
        return RGBA(red: mix(top.red, red), green: mix(top.green, green), blue: mix(top.blue, blue), alpha: alpha)
    }
}

/// The two versions a theme is drawn in; the color scheme picks the one that shows.
public enum ThemeScheme: CaseIterable, Sendable { case light, dark }

/// The sixteen themes of the gallery. A theme sets the color of the windows, the color of the sidebar and an accent of its own, each for
/// the light and the dark version (`docs/research/macos-app-design/theme-reach.md`: nothing else a theme says is promised).
public enum Theme: String, CaseIterable, Codable, Sendable {
    case carrier, graphite, ocean, forest, sunset, paper, rose, lavender, midnight, solarized, nord, gruvbox, dracula, tokyoNight, catppuccin, oneDark

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .carrier: Copy.choiceThemeCarrier(bundle: bundle, locale: locale)
        case .graphite: Copy.choiceThemeGraphite(bundle: bundle, locale: locale)
        case .ocean: Copy.choiceThemeOcean(bundle: bundle, locale: locale)
        case .forest: Copy.choiceThemeForest(bundle: bundle, locale: locale)
        case .sunset: Copy.choiceThemeSunset(bundle: bundle, locale: locale)
        case .paper: Copy.choiceThemePaper(bundle: bundle, locale: locale)
        case .rose: Copy.choiceThemeRose(bundle: bundle, locale: locale)
        case .lavender: Copy.choiceThemeLavender(bundle: bundle, locale: locale)
        case .midnight: Copy.choiceThemeMidnight(bundle: bundle, locale: locale)
        case .solarized: Copy.choiceThemeSolarized(bundle: bundle, locale: locale)
        case .nord: Copy.choiceThemeNord(bundle: bundle, locale: locale)
        case .gruvbox: Copy.choiceThemeGruvbox(bundle: bundle, locale: locale)
        case .dracula: Copy.choiceThemeDracula(bundle: bundle, locale: locale)
        case .tokyoNight: Copy.choiceThemeTokyoNight(bundle: bundle, locale: locale)
        case .catppuccin: Copy.choiceThemeCatppuccin(bundle: bundle, locale: locale)
        case .oneDark: Copy.choiceThemeOneDark(bundle: bundle, locale: locale)
        }
    }

    /// The window, the sidebar and the accent of one version (`design/tokens.json`). Carrier's has no accent of its own: it keeps the Mac's.
    fileprivate func colors(_ scheme: ThemeScheme) -> ThemeColors {
        guard let versions = Tokens.themes[rawValue] else { preconditionFailure("design/tokens.json has no theme \"\(rawValue)\"") }
        return scheme == .dark ? versions.dark : versions.light
    }
}

/// The accent the person picked: one of seven colors, or any color of their own. The raw value is what is stored: a preset's name, or
/// `#rrggbb` for their own. One value for both versions of a theme.
public struct AccentColor: RawRepresentable, CaseIterable, Hashable, Sendable {
    public let rawValue: String

    private static let presets = Tokens.accents

    public static let blue = AccentColor(preset: "blue"), purple = AccentColor(preset: "purple"), pink = AccentColor(preset: "pink"), red = AccentColor(preset: "red")
    public static let orange = AccentColor(preset: "orange"), green = AccentColor(preset: "green"), graphite = AccentColor(preset: "graphite")
    /// The presets of `design/tokens.json`, not their own color.
    public static let allCases = presets.map { AccentColor(preset: $0.name) }

    private init(preset name: String) { rawValue = name }

    /// Nil for a value that is neither a preset's name nor `#` and six hex digits.
    public init?(rawValue: String) {
        guard Self.presets.contains(where: { $0.name == rawValue }) || Self.hex(rawValue) != nil else { return nil }
        self.rawValue = rawValue
    }

    /// The person's own color.
    public static func own(_ color: RGBA) -> AccentColor {
        func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        let hex = String(format: "#%02x%02x%02x", byte(color.red), byte(color.green), byte(color.blue))
        return AccentColor(rawValue: hex)!
    }

    private static func hex(_ text: String) -> UInt32? {
        guard text.count == 7, text.hasPrefix("#") else { return nil }
        return UInt32(text.dropFirst(), radix: 16)
    }

    public var isCustom: Bool { Self.hex(rawValue) != nil }

    /// A preset's name in the app's language; `#rrggbb` is the person's own color. A preset `design/tokens.json` adds is shown by its own name until it has a key.
    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch rawValue {
        case "blue": Copy.choiceAccentBlue(bundle: bundle, locale: locale)
        case "purple": Copy.choiceAccentPurple(bundle: bundle, locale: locale)
        case "pink": Copy.choiceAccentPink(bundle: bundle, locale: locale)
        case "red": Copy.choiceAccentRed(bundle: bundle, locale: locale)
        case "orange": Copy.choiceAccentOrange(bundle: bundle, locale: locale)
        case "green": Copy.choiceAccentGreen(bundle: bundle, locale: locale)
        case "graphite": Copy.choiceAccentGraphite(bundle: bundle, locale: locale)
        default: isCustom ? Copy.choiceAccentCustom(bundle: bundle, locale: locale) : capitalizingFirst(rawValue)
        }
    }

    public var color: RGBA { RGBA(hex: Self.hex(rawValue) ?? Self.presets.first { $0.name == rawValue }?.hex ?? 0) }
}

/// How much of the accent shows on the backgrounds.
public enum Tint: String, CaseIterable, Sendable {
    case off, subtle, strong

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .off: Copy.choiceTintOff(bundle: bundle, locale: locale)
        case .subtle: Copy.choiceTintSubtle(bundle: bundle, locale: locale)
        case .strong: Copy.choiceTintStrong(bundle: bundle, locale: locale)
        }
    }

    /// The accent's opacity over the surface: 0.06 and 0.14 read well on Forest (the spike's note).
    public var opacity: Double {
        switch self {
        case .off: 0
        case .subtle: 0.06
        case .strong: 0.14
        }
    }
}

/// What the app paints for a theme: the windows, the sidebar, and the accent (nil is the Mac's own).
public struct ThemeSurfaces: Equatable, Sendable {
    public var window: RGBA
    public var sidebar: RGBA
    public var accent: RGBA?
}

/// The surface colors and the accent for a theme, a scheme, an accent choice (nil is the theme's own), a tint and whether windows are
/// translucent. Solid draws every surface opaque; translucent lets the sidebar through a little, and Carrier's own surfaces are left to
/// the system. The tint is the theme's own accent laid over the surface at its opacity; the accent chosen is only returned, for the elements.
public func themeSurfaces(_ theme: Theme, scheme: ThemeScheme, accent: AccentColor? = nil, tint: Tint = .off, translucent: Bool) -> ThemeSurfaces {
    let colors = theme.colors(scheme)
    let chosen = accent.map(\.color) ?? colors.accent.map { RGBA(hex: $0) }
    let system = theme == .carrier && translucent
    var window = system ? RGBA.clear : RGBA(hex: colors.window)
    var sidebar = system ? RGBA.clear : RGBA(hex: colors.sidebar, alpha: translucent ? 0.6 : 1)
    // The tint is the theme's own color, never the accent the person chose for the elements: picking a color for the buttons must not paint
    // the windows. Carrier's tint over the system's surface is its accent alone; the Mac's own accent is the blue of its default
    if tint != .off {
        let over = colors.accent.map { RGBA(hex: $0) } ?? RGBA(hex: scheme == .dark ? Tokens.Accent.system.dark : Tokens.Accent.system.light)
        let layer = RGBA(red: over.red, green: over.green, blue: over.blue, alpha: tint.opacity)
        window = window.covered(by: layer)
        sidebar = sidebar.covered(by: layer)
    }
    return ThemeSurfaces(window: window, sidebar: sidebar, accent: chosen)
}
