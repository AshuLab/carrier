import Foundation

public extension RGBA {
    /// Lowercase `#rrggbb` hex string accepted by Ghostty configuration fields.
    var hexString: String {
        func byte(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
    }

    /// WCAG 2.1 relative luminance assuming sRGB components in `[0, 1]`.
    var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            let clamped = min(max(component, 0), 1)
            return clamped <= 0.03928 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2.1 contrast ratio in `[1, 21]`.
    func contrastRatio(with other: RGBA) -> Double {
        let l1 = relativeLuminance
        let l2 = other.relativeLuminance
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func blended(toward target: RGBA, fraction: Double) -> RGBA {
        let t = min(max(fraction, 0), 1)
        return RGBA(
            red: red + (target.red - red) * t,
            green: green + (target.green - green) * t,
            blue: blue + (target.blue - blue) * t,
            alpha: alpha + (target.alpha - alpha) * t
        )
    }
}

/// Shape of Ghostty's terminal cursor.
public enum TerminalCursorStyleChoice: String, CaseIterable, Codable, Sendable {
    case block
    case bar
    case underline

    public var title: String { rawValue.capitalized }
}

/// How macOS Option keys map to Alt/Meta inside Ghostty.
public enum TerminalOptionAsAlt: String, CaseIterable, Codable, Sendable {
    case off = "false"
    case left = "left"
    case right = "right"
    case both = "true"

    public var title: String {
        switch self {
        case .off: "Off"
        case .left: "Left Option"
        case .right: "Right Option"
        case .both: "Both"
        }
    }
}

/// Scrollback history limit passed to Ghostty (`scrollback-limit`, in bytes).
public enum TerminalScrollbackLimit: Int, CaseIterable, Codable, Sendable {
    case mb1 = 1_000_000
    case mb10 = 10_000_000
    case mb50 = 50_000_000
    case mb100 = 100_000_000

    public var title: String {
        switch self {
        case .mb1: "1 MB"
        case .mb10: "10 MB"
        case .mb50: "50 MB"
        case .mb100: "100 MB"
        }
    }
}

/// Terminal-specific preferences stored alongside Carrier appearance settings for Settings -> Terminal controls.
public struct TerminalSettings: Equatable, Codable, Sendable {
    public static let fontSizeRange: ClosedRange<Double> = 9...24
    public static let paddingRange: ClosedRange<Double> = 0...32
    public static let minimumContrastRange: ClosedRange<Double> = 1...21

    public static let defaultCursorStyle: TerminalCursorStyleChoice = .block
    public static let defaultCursorBlink = true
    public static let defaultPaddingX: Double = 10
    public static let defaultPaddingY: Double = 8
    public static let defaultMinimumContrast: Double = 3.0
    public static let defaultConfirmCloseRunningProcess = true
    public static let defaultPinPromptToBottom = false
    public static let defaultFontThicken = false
    public static let defaultDimInactivePanes = false
    public static let defaultFocusFollowsMouse = false
    public static let defaultOptionAsAlt: TerminalOptionAsAlt = .off
    public static let defaultCopyOnSelect = false
    public static let defaultScrollbackLimit: TerminalScrollbackLimit = .mb10

    /// Explicit theme override; `nil` follows Carrier's global app theme.
    public var themeOverride: Theme?
    /// Explicit font family override; `nil` follows Carrier's monospace font setting.
    public var fontFamilyOverride: String?
    /// Explicit font size override in points; `nil` follows Carrier's monospace size setting.
    public var fontSizeOverride: Double?
    /// Explicit ligature override; `nil` follows Carrier's monospace ligatures setting.
    public var fontLigaturesOverride: Bool?
    public var fontThicken: Bool
    public var cursorStyle: TerminalCursorStyleChoice
    public var cursorBlink: Bool
    public var paddingX: Double
    public var paddingY: Double
    public var minimumContrast: Double
    public var dimInactivePanes: Bool
    public var focusFollowsMouse: Bool
    public var optionAsAlt: TerminalOptionAsAlt
    public var copyOnSelect: Bool
    public var scrollbackLimit: TerminalScrollbackLimit
    public var confirmCloseRunningProcess: Bool
    /// Anchors new interactive Zsh prompts at the bottom row of the viewport (Warp-style) without touching user dotfiles.
    public var pinPromptToBottom: Bool

    public init(
        themeOverride: Theme? = nil,
        fontFamilyOverride: String? = nil,
        fontSizeOverride: Double? = nil,
        fontLigaturesOverride: Bool? = nil,
        fontThicken: Bool = Self.defaultFontThicken,
        cursorStyle: TerminalCursorStyleChoice = Self.defaultCursorStyle,
        cursorBlink: Bool = Self.defaultCursorBlink,
        paddingX: Double = Self.defaultPaddingX,
        paddingY: Double = Self.defaultPaddingY,
        minimumContrast: Double = Self.defaultMinimumContrast,
        dimInactivePanes: Bool = Self.defaultDimInactivePanes,
        focusFollowsMouse: Bool = Self.defaultFocusFollowsMouse,
        optionAsAlt: TerminalOptionAsAlt = Self.defaultOptionAsAlt,
        copyOnSelect: Bool = Self.defaultCopyOnSelect,
        scrollbackLimit: TerminalScrollbackLimit = Self.defaultScrollbackLimit,
        confirmCloseRunningProcess: Bool = Self.defaultConfirmCloseRunningProcess,
        pinPromptToBottom: Bool = Self.defaultPinPromptToBottom
    ) {
        self.themeOverride = themeOverride
        self.fontFamilyOverride = Self.cleanFontFamily(fontFamilyOverride)
        self.fontSizeOverride = fontSizeOverride.map(Self.clampFontSize)
        self.fontLigaturesOverride = fontLigaturesOverride
        self.fontThicken = fontThicken
        self.cursorStyle = cursorStyle
        self.cursorBlink = cursorBlink
        self.paddingX = Self.clampPadding(paddingX)
        self.paddingY = Self.clampPadding(paddingY)
        self.minimumContrast = Self.clampMinimumContrast(minimumContrast)
        self.dimInactivePanes = dimInactivePanes
        self.focusFollowsMouse = focusFollowsMouse
        self.optionAsAlt = optionAsAlt
        self.copyOnSelect = copyOnSelect
        self.scrollbackLimit = scrollbackLimit
        self.confirmCloseRunningProcess = confirmCloseRunningProcess
        self.pinPromptToBottom = pinPromptToBottom
    }

    public static func cleanFontFamily(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false else {
            return nil
        }
        guard trimmed != MonospaceSettings.systemFamily,
              trimmed.unicodeScalars.contains(where: { CharacterSet.newlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) == false
        else {
            return nil
        }
        return trimmed
    }

    public static func clampFontSize(_ value: Double) -> Double {
        guard value.isFinite else { return Double(MonospaceSettings.defaultSize) }
        return min(max(value, fontSizeRange.lowerBound), fontSizeRange.upperBound)
    }

    public static func clampPadding(_ value: Double) -> Double {
        guard value.isFinite else { return defaultPaddingX }
        return min(max(value, paddingRange.lowerBound), paddingRange.upperBound)
    }

    public static func clampMinimumContrast(_ value: Double) -> Double {
        guard value.isFinite else { return defaultMinimumContrast }
        return min(max(value, minimumContrastRange.lowerBound), minimumContrastRange.upperBound)
    }

    public func effectiveTheme(appTheme: Theme) -> Theme {
        themeOverride ?? appTheme
    }

    public func effectiveFontFamily(appMonospace: MonospaceSettings) -> String? {
        Self.cleanFontFamily(fontFamilyOverride ?? appMonospace.family)
    }

    public func effectiveFontSize(appMonospace: MonospaceSettings) -> Double {
        Self.clampFontSize(fontSizeOverride ?? Double(appMonospace.size))
    }

    public func effectiveLigatures(appMonospace: MonospaceSettings) -> Bool {
        fontLigaturesOverride ?? appMonospace.ligatures
    }

    /// Installed font families plus any saved custom override so Settings never drops or hides an existing choice.
    public static func availableFontFamilies(installed: [String], currentOverride: String?) -> [String] {
        guard let current = cleanFontFamily(currentOverride),
              installed.contains(current) == false
        else {
            return installed
        }
        return [current] + installed
    }

    /// Integer point sizes across `fontSizeRange`, retaining any rounded stored override within bounds.
    public static func availableFontSizes(currentOverride: Double?) -> [Int] {
        var sizes = Array(Int(fontSizeRange.lowerBound)...Int(fontSizeRange.upperBound))
        if let currentOverride, currentOverride.isFinite {
            let rounded = Int(clampFontSize(currentOverride).rounded())
            if sizes.contains(rounded) == false {
                sizes.append(rounded)
                sizes.sort()
            }
        }
        return sizes
    }

    public static func minimumContrastLabel(_ value: Double) -> String {
        let clamped = clampMinimumContrast(value)
        if clamped <= minimumContrastRange.lowerBound + 0.001 {
            return "Off · 1.0 : 1"
        }
        return String(format: "%.1f : 1", clamped)
    }
}

/// Complete high-contrast appearance & typography profile fed into Ghostty's `TerminalConfiguration`.
public struct TerminalAppearanceProfile: Equatable, Sendable {
    public let theme: Theme
    public let scheme: ThemeScheme
    public let accent: AccentColor?
    public let tint: Tint
    public let translucent: Bool
    public let isSurfaceTranslucent: Bool
    /// Solid effective RGB background used by Ghostty for contrast calculations and subpixel blending.
    public let background: RGBA
    /// Window surface color matching `themeSurfaces(..., translucent: translucent)` for SwiftUI chrome behind/around panes.
    public let chromeBackground: RGBA
    public let backgroundOpacity: Double
    public let foreground: RGBA
    public let boldColor: RGBA
    public let selectionBackground: RGBA
    public let selectionForeground: RGBA
    public let cursorColor: RGBA
    public let cursorText: RGBA
    /// 16-color ANSI palette (0...15) tailored for the active Carrier theme and light/dark scheme.
    public let palette: [RGBA]
    public let fontFamily: String?
    public let fontSize: Double
    public let ligatures: Bool
    public let fontThicken: Bool
    public let cursorStyle: TerminalCursorStyleChoice
    public let cursorBlink: Bool
    public let paddingX: Double
    public let paddingY: Double
    public let minimumContrast: Double
    public let dimInactivePanes: Bool
    public let focusFollowsMouse: Bool
    public let optionAsAlt: TerminalOptionAsAlt
    public let copyOnSelect: Bool
    public let scrollbackLimit: TerminalScrollbackLimit

    public init(
        theme: Theme,
        scheme: ThemeScheme = .dark,
        accent: AccentColor? = nil,
        tint: Tint = .off,
        translucent: Bool = false,
        monospace: MonospaceSettings = MonospaceSettings(),
        terminalSettings: TerminalSettings = TerminalSettings()
    ) {
        let resolvedTheme = terminalSettings.effectiveTheme(appTheme: theme)
        let solidSurfaces = themeSurfaces(resolvedTheme, scheme: scheme, accent: accent, tint: tint, translucent: false)
        let chromeSurfaces = themeSurfaces(resolvedTheme, scheme: scheme, accent: accent, tint: tint, translucent: translucent)
        let background = solidSurfaces.window
        let resolvedAccent = solidSurfaces.accent ?? RGBA(hex: scheme == .dark ? 0x0a84ff : 0x0066cc)
        let isSurfaceTranslucent = resolvedTheme == .carrier && translucent

        let preferredInk = RGBA(hex: scheme == .dark ? 0xf2f4f8 : 0x15171c)
        let fallbackDark = RGBA(hex: 0x0a0b0e)
        let fallbackLight = RGBA(hex: 0xffffff)
        let bestInk: RGBA
        if preferredInk.contrastRatio(with: background) >= 7.0 {
            bestInk = preferredInk
        } else {
            bestInk = fallbackLight.contrastRatio(with: background) >= fallbackDark.contrastRatio(with: background)
                ? fallbackLight
                : fallbackDark
        }

        let preferredBold = scheme == .dark ? fallbackLight : fallbackDark
        let boldColor = preferredBold.contrastRatio(with: background) >= bestInk.contrastRatio(with: background)
            ? preferredBold
            : bestInk

        let selectionAlpha = scheme == .dark ? 0.34 : 0.24
        let selectionBackground = background.covered(
            by: RGBA(red: resolvedAccent.red, green: resolvedAccent.green, blue: resolvedAccent.blue, alpha: selectionAlpha)
        )
        let selectionForeground: RGBA
        if bestInk.contrastRatio(with: selectionBackground) >= 6.5 {
            selectionForeground = bestInk
        } else {
            selectionForeground = fallbackLight.contrastRatio(with: selectionBackground) >= fallbackDark.contrastRatio(with: selectionBackground)
                ? fallbackLight
                : fallbackDark
        }

        var cursorColor = resolvedAccent
        if cursorColor.contrastRatio(with: background) < 3.5 {
            for step in 1...10 {
                let candidate = resolvedAccent.blended(toward: bestInk, fraction: Double(step) * 0.1)
                cursorColor = candidate
                if candidate.contrastRatio(with: background) >= 3.5 { break }
            }
        }
        let pureBlack = RGBA(hex: 0x000000)
        let cursorText = fallbackLight.contrastRatio(with: cursorColor) >= pureBlack.contrastRatio(with: cursorColor)
            ? fallbackLight
            : pureBlack

        self.theme = resolvedTheme
        self.scheme = scheme
        self.accent = accent
        self.tint = tint
        self.translucent = translucent
        self.isSurfaceTranslucent = isSurfaceTranslucent
        self.background = background
        self.chromeBackground = chromeSurfaces.window
        self.backgroundOpacity = isSurfaceTranslucent ? 0.0 : 1.0
        self.foreground = bestInk
        self.boldColor = boldColor
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.cursorColor = cursorColor
        self.cursorText = cursorText
        self.palette = themeTerminalPalette(for: resolvedTheme, scheme: scheme)
        self.fontFamily = terminalSettings.effectiveFontFamily(appMonospace: monospace)
        self.fontSize = terminalSettings.effectiveFontSize(appMonospace: monospace)
        self.ligatures = terminalSettings.effectiveLigatures(appMonospace: monospace)
        self.fontThicken = terminalSettings.fontThicken
        self.cursorStyle = terminalSettings.cursorStyle
        self.cursorBlink = terminalSettings.cursorBlink
        self.paddingX = terminalSettings.paddingX
        self.paddingY = terminalSettings.paddingY
        self.minimumContrast = terminalSettings.minimumContrast
        self.dimInactivePanes = terminalSettings.dimInactivePanes
        self.focusFollowsMouse = terminalSettings.focusFollowsMouse
        self.optionAsAlt = terminalSettings.optionAsAlt
        self.copyOnSelect = terminalSettings.copyOnSelect
        self.scrollbackLimit = terminalSettings.scrollbackLimit
    }

    /// Adjusts a terminal foreground color toward `foreground` until it meets `minimumContrast` against `background`.
    public func adjustedForMinimumContrast(_ color: RGBA) -> RGBA {
        guard minimumContrast > 1.0 else { return color }
        if color.contrastRatio(with: background) >= minimumContrast {
            return color
        }
        var adjusted = color
        for step in 1...20 {
            let candidate = color.blended(toward: foreground, fraction: Double(step) * 0.05)
            adjusted = candidate
            if candidate.contrastRatio(with: background) >= minimumContrast {
                break
            }
        }
        return adjusted
    }
}

private func hexPalette(_ hexValues: [UInt32]) -> [RGBA] {
    hexValues.map { RGBA(hex: $0) }
}

/// Curated 16-color ANSI palettes (0...7 normal, 8...15 bright) harmonized with each of Carrier's 9 themes in both light and dark modes.
private func themeTerminalPalette(for theme: Theme, scheme: ThemeScheme) -> [RGBA] {
    switch (theme, scheme) {
    case (.carrier, .dark):
        return hexPalette([
            0x161618, 0xff6961, 0x32d74b, 0xffd60a, 0x409cff, 0xda8fff, 0x64d2ff, 0xd8dae0,
            0x787880, 0xff8a80, 0x5de66f, 0xffe34d, 0x70b8ff, 0xe6b3ff, 0x90e0ff, 0xf5f5f7,
        ])
    case (.carrier, .light):
        return hexPalette([
            0x1c1c1e, 0xb82222, 0x166e30, 0x7d4f00, 0x0054b0, 0x7c1e96, 0x006388, 0xd1d1d6,
            0x55555c, 0xc72929, 0x1a7d37, 0x8c5900, 0x005fc7, 0x8f24ab, 0x00719c, 0xffffff,
        ])
    case (.graphite, .dark):
        return hexPalette([
            0x121315, 0xf07178, 0x6cc67d, 0xe5c07b, 0x7aa2d8, 0xc28be8, 0x68b7c4, 0xcaccd2,
            0x787b85, 0xf78c92, 0x8ad998, 0xf0d297, 0x98bbf0, 0xd6aaf5, 0x8ad0dc, 0xf0f1f4,
        ])
    case (.graphite, .light):
        return hexPalette([
            0x1f2023, 0xa82a30, 0x1b6634, 0x7a5410, 0x26528c, 0x6f3694, 0x145f69, 0xd4d4d8,
            0x56585f, 0xb8333a, 0x21753d, 0x8a5f13, 0x2d61a6, 0x803ea8, 0x196e78, 0xf8f8fa,
        ])
    case (.ocean, .dark):
        return hexPalette([
            0x0b141c, 0xff6e73, 0x4cd49a, 0xf2c96b, 0x32ade6, 0x9b9eff, 0x4de0dc, 0xd0e2f0,
            0x6a899e, 0xff8f94, 0x6ee6b3, 0xffd987, 0x60c6f7, 0xb8baff, 0x7ef2ee, 0xedf6fc,
        ])
    case (.ocean, .light):
        return hexPalette([
            0x112536, 0xa82532, 0x0d684a, 0x7a5200, 0x076499, 0x4e43b5, 0x00636b, 0xc8dce9,
            0x4a687d, 0xba2c3b, 0x117856, 0x8a5d00, 0x0973b0, 0x5c50cc, 0x00727c, 0xf7fbfe,
        ])
    case (.forest, .dark):
        return hexPalette([
            0x0d140f, 0xf2746b, 0x30d158, 0xd8c456, 0x5ca8e6, 0xc68ae8, 0x4fd1b5, 0xd1dfd3,
            0x6b8771, 0xff928a, 0x5ce67e, 0xebd873, 0x7ec0f5, 0xdba6f7, 0x73e6cd, 0xedf5ee,
        ])
    case (.forest, .light):
        return hexPalette([
            0x142619, 0xa82a24, 0x137330, 0x755705, 0x1b5894, 0x6f3596, 0x0d6658, 0xcce0ce,
            0x4d6b55, 0xb8322b, 0x188238, 0x856407, 0x2167ad, 0x803eab, 0x117565, 0xf7fbf7,
        ])
    case (.sunset, .dark):
        return hexPalette([
            0x17110d, 0xff6e5e, 0x7ec96b, 0xff9f0a, 0x6ba8eb, 0xe67eb8, 0x5cc4b8, 0xe6d6c8,
            0x8c7668, 0xff8f82, 0x9ad989, 0xffb84d, 0x8bc0f7, 0xf59dce, 0x7ddbd0, 0xfaf3ed,
        ])
    case (.sunset, .light):
        return hexPalette([
            0x2e1e14, 0xab2920, 0x206820, 0x874600, 0x1e5291, 0x8c2461, 0x10615c, 0xe5d3be,
            0x6b5547, 0xbd3127, 0x287828, 0x995100, 0x2561ab, 0x9e2c6f, 0x15706a, 0xfffaf5,
        ])
    case (.paper, .dark):
        return hexPalette([
            0x1a1918, 0xf0756e, 0x6fc47b, 0xe8be64, 0x6ea8ff, 0xc98be6, 0x5cc7c7, 0xdcd8d0,
            0x827e78, 0xff948e, 0x8fd699, 0xf7d281, 0x91beff, 0xdbabf2, 0x80dede, 0xf5f2eb,
        ])
    case (.paper, .light):
        return hexPalette([
            0x24221e, 0xa82924, 0x1a662e, 0x7a5004, 0x0058b5, 0x703294, 0x0e6169, 0xded9cc,
            0x615c54, 0xba312b, 0x217537, 0x8a5b06, 0x0066cf, 0x823bab, 0x137078, 0xfcfbf7,
        ])
    case (.rose, .dark):
        return hexPalette([
            0x170e12, 0xff6b9a, 0x6fd195, 0xf0be6c, 0x7baaf7, 0xe68ae0, 0x66c9d1, 0xe6d4da,
            0x8c6d79, 0xff8fb3, 0x90e3b0, 0xfad18c, 0x9cc0ff, 0xf5abef, 0x8ae0e8, 0xfaf0f4,
        ])
    case (.rose, .light):
        return hexPalette([
            0x2b171f, 0xb01e4e, 0x16683d, 0x7d4b06, 0x2352a3, 0x852380, 0x0f5f69, 0xe8cfd6,
            0x6e515c, 0xc4265b, 0x1c7848, 0x8f5708, 0x2a60bd, 0x992b93, 0x146e78, 0xfff7f9,
        ])
    case (.lavender, .dark):
        return hexPalette([
            0x120f17, 0xf2748b, 0x6ad19e, 0xebd073, 0x82aaff, 0xb58cff, 0x69d1e0, 0xdcd4eb,
            0x7e7291, 0xff94a8, 0x8ae3b7, 0xf7e092, 0xa3c2ff, 0xc9abff, 0x8ce5f2, 0xf3effb,
        ])
    case (.lavender, .light):
        return hexPalette([
            0x211930, 0xa82442, 0x146642, 0x7a5206, 0x274fad, 0x682bd6, 0x0e606e, 0xd9cff0,
            0x5e5078, 0xba2c4e, 0x1a754d, 0x8a5e08, 0x2f5ec9, 0x7938ed, 0x136f7e, 0xfaf8ff,
        ])
    case (.midnight, .dark):
        return hexPalette([
            0x070a12, 0xff6e7a, 0x4cd99c, 0xf2c864, 0x5ea3ff, 0xb88eff, 0x2dd4bf, 0xd0d8eb,
            0x697696, 0xff919b, 0x6ee8b3, 0xfad984, 0x85baff, 0xccadff, 0x5ce6d4, 0xeef2fa,
        ])
    case (.midnight, .light):
        return hexPalette([
            0x12182b, 0xa82534, 0x0e6646, 0x7a5005, 0x1d4aa3, 0x6231b0, 0x0a695b, 0xcad0e8,
            0x4e597a, 0xba2c3d, 0x137551, 0x8a5b07, 0x2458bf, 0x733cc9, 0x0e7868, 0xf7f8fc,
        ])
    }
}
