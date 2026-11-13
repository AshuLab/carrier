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

/// Terminal-specific preferences stored alongside Carrier appearance settings for future Settings -> Terminal controls.
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

    /// Explicit theme override; `nil` follows Carrier's global app theme.
    public var themeOverride: Theme?
    /// Explicit font family override; `nil` follows Carrier's monospace font setting.
    public var fontFamilyOverride: String?
    /// Explicit font size override in points; `nil` follows Carrier's monospace size setting.
    public var fontSizeOverride: Double?
    /// Explicit ligature override; `nil` follows Carrier's monospace ligatures setting.
    public var fontLigaturesOverride: Bool?
    public var cursorStyle: TerminalCursorStyleChoice
    public var cursorBlink: Bool
    public var paddingX: Double
    public var paddingY: Double
    public var minimumContrast: Double
    public var confirmCloseRunningProcess: Bool

    public init(
        themeOverride: Theme? = nil,
        fontFamilyOverride: String? = nil,
        fontSizeOverride: Double? = nil,
        fontLigaturesOverride: Bool? = nil,
        cursorStyle: TerminalCursorStyleChoice = Self.defaultCursorStyle,
        cursorBlink: Bool = Self.defaultCursorBlink,
        paddingX: Double = Self.defaultPaddingX,
        paddingY: Double = Self.defaultPaddingY,
        minimumContrast: Double = Self.defaultMinimumContrast,
        confirmCloseRunningProcess: Bool = Self.defaultConfirmCloseRunningProcess
    ) {
        self.themeOverride = themeOverride
        self.fontFamilyOverride = Self.cleanFontFamily(fontFamilyOverride)
        self.fontSizeOverride = fontSizeOverride.map(Self.clampFontSize)
        self.fontLigaturesOverride = fontLigaturesOverride
        self.cursorStyle = cursorStyle
        self.cursorBlink = cursorBlink
        self.paddingX = Self.clampPadding(paddingX)
        self.paddingY = Self.clampPadding(paddingY)
        self.minimumContrast = Self.clampMinimumContrast(minimumContrast)
        self.confirmCloseRunningProcess = confirmCloseRunningProcess
    }

    public static func cleanFontFamily(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false else {
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
        let raw = fontFamilyOverride ?? appMonospace.family
        guard raw != MonospaceSettings.systemFamily, raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return raw
    }

    public func effectiveFontSize(appMonospace: MonospaceSettings) -> Double {
        Self.clampFontSize(fontSizeOverride ?? Double(appMonospace.size))
    }

    public func effectiveLigatures(appMonospace: MonospaceSettings) -> Bool {
        fontLigaturesOverride ?? appMonospace.ligatures
    }
}

/// Complete high-contrast appearance & typography profile fed into Ghostty's `TerminalConfiguration`.
public struct TerminalAppearanceProfile: Equatable, Sendable {
    public let theme: Theme
    public let scheme: ThemeScheme
    public let background: RGBA
    public let foreground: RGBA
    public let selectionBackground: RGBA
    public let selectionForeground: RGBA
    public let cursorColor: RGBA
    public let fontFamily: String?
    public let fontSize: Double
    public let ligatures: Bool
    public let cursorStyle: TerminalCursorStyleChoice
    public let cursorBlink: Bool
    public let paddingX: Double
    public let paddingY: Double
    public let minimumContrast: Double

    public init(
        theme: Theme,
        scheme: ThemeScheme = .dark,
        accent: AccentColor? = nil,
        tint: Tint = .off,
        monospace: MonospaceSettings = MonospaceSettings(),
        terminalSettings: TerminalSettings = TerminalSettings()
    ) {
        let resolvedTheme = terminalSettings.effectiveTheme(appTheme: theme)
        let surfaces = themeSurfaces(resolvedTheme, scheme: scheme, accent: accent, tint: tint, translucent: false)
        let background = surfaces.window
        let resolvedAccent = surfaces.accent ?? RGBA(hex: scheme == .dark ? 0x0a84ff : 0x0066cc)

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

        self.theme = resolvedTheme
        self.scheme = scheme
        self.background = background
        self.foreground = bestInk
        self.selectionBackground = selectionBackground
        self.selectionForeground = selectionForeground
        self.cursorColor = cursorColor
        self.fontFamily = terminalSettings.effectiveFontFamily(appMonospace: monospace)
        self.fontSize = terminalSettings.effectiveFontSize(appMonospace: monospace)
        self.ligatures = terminalSettings.effectiveLigatures(appMonospace: monospace)
        self.cursorStyle = terminalSettings.cursorStyle
        self.cursorBlink = terminalSettings.cursorBlink
        self.paddingX = terminalSettings.paddingX
        self.paddingY = terminalSettings.paddingY
        self.minimumContrast = terminalSettings.minimumContrast
    }
}
