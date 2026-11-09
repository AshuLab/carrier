import Foundation

/// A color the theme hands out: components from 0 to 1, so the value is pure and the app turns it into a `Color`.
public struct RGBA: Equatable {
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
public enum ThemeScheme: CaseIterable { case light, dark }

/// The six themes of the gallery. A theme sets the color of the windows, the color of the sidebar and an accent of its own, each for
/// the light and the dark version (`docs/research/macos-app-design/theme-reach.md`: nothing else a theme says is promised).
public enum Theme: String, CaseIterable {
    case carrier, graphite, ocean, forest, sunset, paper

    public var title: String { rawValue.capitalized }

    /// The window, the sidebar and the accent of one version. Carrier's has no accent of its own: it keeps the Mac's.
    fileprivate func colors(_ scheme: ThemeScheme) -> (window: UInt32, sidebar: UInt32, accent: UInt32?) {
        switch (self, scheme) {
        case (.carrier, .dark): (0x1c1c1e, 0x2f2f33, nil)
        case (.carrier, .light): (0xf2f2f7, 0xdcdce2, nil)
        case (.graphite, .dark): (0x17181a, 0x26272a, 0x98989d)
        case (.graphite, .light): (0xececee, 0xd9d9dc, 0x636366)
        case (.ocean, .dark): (0x0f1b24, 0x18304a, 0x32ade6)
        case (.ocean, .light): (0xeaf3fa, 0xcfe3f2, 0x0a7fc0)
        case (.forest, .dark): (0x121a14, 0x1d2f22, 0x30d158)
        case (.forest, .light): (0xeef5ee, 0xd3e6d6, 0x1f9d45)
        case (.sunset, .dark): (0x1f1712, 0x34241a, 0xff9f0a)
        case (.sunset, .light): (0xfbf1e6, 0xf1dcc3, 0xd97706)
        case (.paper, .dark): (0x222120, 0x32302d, 0x6ea8ff)
        case (.paper, .light): (0xf6f4ef, 0xe6e1d4, 0x007aff)
        }
    }
}

/// The seven colors the accent can be, one value for both versions.
public enum AccentColor: String, CaseIterable {
    case blue, purple, pink, red, orange, green, graphite

    public var title: String { rawValue.capitalized }

    fileprivate var hex: UInt32 {
        switch self {
        case .blue: 0x0a84ff
        case .purple: 0xbf5af2
        case .pink: 0xff375f
        case .red: 0xff453a
        case .orange: 0xff9f0a
        case .green: 0x30d158
        case .graphite: 0x8e8e93
        }
    }

    public var color: RGBA { RGBA(hex: hex) }
}

/// How much of the accent shows on the backgrounds.
public enum Tint: String, CaseIterable {
    case off, subtle, strong

    public var title: String { rawValue.capitalized }

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
public struct ThemeSurfaces: Equatable {
    public var window: RGBA
    public var sidebar: RGBA
    public var accent: RGBA?
}

/// The surface colors and the accent for a theme, a scheme, an accent choice (nil is the theme's own), a tint and whether windows are
/// translucent. Solid draws every surface opaque; translucent lets the sidebar through a little, and Carrier's own surfaces are left to
/// the system. The tint is the accent laid over the surface at its opacity.
public func themeSurfaces(_ theme: Theme, scheme: ThemeScheme, accent: AccentColor? = nil, tint: Tint = .off, translucent: Bool) -> ThemeSurfaces {
    let colors = theme.colors(scheme)
    let chosen = accent.map(\.color) ?? colors.accent.map { RGBA(hex: $0) }
    let system = theme == .carrier && translucent
    var window = system ? RGBA.clear : RGBA(hex: colors.window)
    var sidebar = system ? RGBA.clear : RGBA(hex: colors.sidebar, alpha: translucent ? 0.6 : 1)
    // Carrier's tint over the system's surface is the accent alone; the Mac's own accent is the blue of its default
    if let over = chosen ?? (tint == .off ? nil : RGBA(hex: scheme == .dark ? 0x0a84ff : 0x007aff)) {
        let layer = RGBA(red: over.red, green: over.green, blue: over.blue, alpha: tint.opacity)
        window = window.covered(by: layer)
        sidebar = sidebar.covered(by: layer)
    }
    return ThemeSurfaces(window: window, sidebar: sidebar, accent: chosen)
}
