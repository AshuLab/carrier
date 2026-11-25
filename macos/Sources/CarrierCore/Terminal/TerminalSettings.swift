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

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .block: Copy.terminalCursorStyle(style: .block, bundle: bundle, locale: locale)
        case .bar: Copy.terminalCursorStyle(style: .bar, bundle: bundle, locale: locale)
        case .underline: Copy.terminalCursorStyle(style: .other, bundle: bundle, locale: locale)
        }
    }
}

/// How macOS Option keys map to Alt/Meta inside Ghostty.
public enum TerminalOptionAsAlt: String, CaseIterable, Codable, Sendable {
    case off = "false"
    case left = "left"
    case right = "right"
    case both = "true"

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .off: Copy.terminalOptionAsAlt(which: .off, bundle: bundle, locale: locale)
        case .left: Copy.terminalOptionAsAlt(which: .left, bundle: bundle, locale: locale)
        case .right: Copy.terminalOptionAsAlt(which: .right, bundle: bundle, locale: locale)
        case .both: Copy.terminalOptionAsAlt(which: .other, bundle: bundle, locale: locale)
        }
    }
}

/// Scrollback history limit passed to Ghostty (`scrollback-limit`, in bytes).
public enum TerminalScrollbackLimit: Int, CaseIterable, Codable, Sendable {
    case mb1 = 1_000_000
    case mb10 = 10_000_000
    case mb50 = 50_000_000
    case mb100 = 100_000_000

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        Copy.terminalMegabytes(size: rawValue / 1_000_000, bundle: bundle, locale: locale)
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

    public static func minimumContrastLabel(_ value: Double, bundle: Bundle? = nil, locale: Locale = .current) -> String {
        let clamped = clampMinimumContrast(value)
        if clamped <= minimumContrastRange.lowerBound + 0.001 {
            return Copy.terminalContrastOff(bundle: bundle, locale: locale)
        }
        return Copy.terminalContrastRatio(ratio: String(format: "%.1f", locale: locale, clamped), bundle: bundle, locale: locale)
    }
}
