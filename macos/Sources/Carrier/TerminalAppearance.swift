import AppKit
import CarrierCore
import GhosttyTerminal

/// Maps Carrier theme, palette scheme, and user terminal preferences into Ghostty configurations.
enum TerminalAppearanceMapper {
    static func makeProfile(
        theme: Theme,
        scheme: ThemeScheme,
        preferences: AppPreferences
    ) -> TerminalAppearanceProfile {
        TerminalAppearanceProfile(
            theme: theme,
            scheme: scheme,
            accent: preferences.accent,
            tint: preferences.tint,
            monospace: preferences.monospace,
            terminalSettings: preferences.terminal
        )
    }

    static func ghosttyTheme(for theme: Theme, preferences: AppPreferences) -> TerminalTheme {
        let light = makeProfile(theme: theme, scheme: .light, preferences: preferences)
        let dark = makeProfile(theme: theme, scheme: .dark, preferences: preferences)
        return TerminalTheme(
            light: ghosttyColorConfiguration(for: light),
            dark: ghosttyColorConfiguration(for: dark)
        )
    }

    static func ghosttyBaseConfiguration(for profile: TerminalAppearanceProfile) -> TerminalConfiguration {
        TerminalConfiguration { builder in
            builder.withWindowPaddingX(Int(profile.paddingX.rounded()))
            builder.withWindowPaddingY(Int(profile.paddingY.rounded()))
            builder.withCursorStyle(ghosttyCursorStyle(profile.cursorStyle))
            builder.withCursorStyleBlink(profile.cursorBlink)
            builder.withFontSize(Float(profile.fontSize))
            if let fontFamily = profile.fontFamily {
                builder.withFontFamily(fontFamily)
            }
            builder.withCustom("font-feature", profile.ligatures ? "calt,liga" : "-calt,-liga,-dlig")
        }
    }

    static func ghosttyColorScheme(_ scheme: ThemeScheme) -> TerminalColorScheme {
        switch scheme {
        case .light: .light
        case .dark: .dark
        }
    }

    @MainActor
    static func resolveScheme(_ choice: ColorSchemeChoice) -> ThemeScheme {
        switch choice {
        case .light: return .light
        case .dark: return .dark
        case .system:
            let name = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            return name == .aqua ? .light : .dark
        }
    }

    private static func ghosttyColorConfiguration(for profile: TerminalAppearanceProfile) -> TerminalConfiguration {
        TerminalConfiguration { builder in
            builder.withBackground(profile.background.hexString)
            builder.withForeground(profile.foreground.hexString)
            builder.withSelectionBackground(profile.selectionBackground.hexString)
            builder.withSelectionForeground(profile.selectionForeground.hexString)
            builder.withCursorColor(profile.cursorColor.hexString)
            builder.withMinimumContrast(profile.minimumContrast)
        }
    }

    private static func ghosttyCursorStyle(_ choice: TerminalCursorStyleChoice) -> TerminalCursorStyle {
        switch choice {
        case .block: .block
        case .bar: .bar
        case .underline: .underline
        }
    }
}
