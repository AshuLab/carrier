import Foundation
import Testing

@testable import CarrierCore

@Suite struct ThemeTests {
    private func close(_ a: RGBA, _ b: RGBA) -> Bool {
        abs(a.red - b.red) < 0.001 && abs(a.green - b.green) < 0.001 && abs(a.blue - b.blue) < 0.001 && abs(a.alpha - b.alpha) < 0.001
    }

    @Test func each_theme_has_its_own_surfaces_in_both_schemes() {
        for theme in Theme.allCases {
            let light = themeSurfaces(theme, scheme: .light, translucent: false)
            let dark = themeSurfaces(theme, scheme: .dark, translucent: false)
            #expect(light.window != dark.window && light.sidebar != dark.sidebar, "\(theme) looks the same in both")
            #expect(light.window.alpha == 1 && light.sidebar.alpha == 1 && dark.window.alpha == 1 && dark.sidebar.alpha == 1)
            // Carrier keeps the Mac's accent; every other theme has one of its own, a different one in each version
            #expect((light.accent == nil) == (theme == .carrier))
            if theme != .carrier { #expect(light.accent != dark.accent) }
        }
        #expect(themeSurfaces(.forest, scheme: .dark, translucent: false) == ThemeSurfaces(
            window: RGBA(hex: 0x121a14), sidebar: RGBA(hex: 0x1d2f22), accent: RGBA(hex: 0x30d158)))
        #expect(themeSurfaces(.paper, scheme: .light, translucent: false).window == RGBA(hex: 0xf6f4ef))
    }

    @Test func a_chosen_accent_replaces_the_themes_own_in_both_schemes() {
        for theme in Theme.allCases {
            for scheme in ThemeScheme.allCases {
                #expect(themeSurfaces(theme, scheme: scheme, accent: .purple, translucent: false).accent == AccentColor.purple.color)
            }
        }
        #expect(AccentColor.allCases.count == 7)
    }

    @Test func the_persons_own_accent_is_stored_as_a_hex_and_read_back_and_a_bad_value_is_none() throws {
        let own = AccentColor.own(RGBA(hex: 0x12ab9c))
        #expect(own.rawValue == "#12ab9c" && own.isCustom && own.title(bundle: english.bundle, locale: english.locale) == "Custom")
        #expect(try #require(AccentColor(rawValue: own.rawValue)).color == RGBA(hex: 0x12ab9c))
        #expect(themeSurfaces(.forest, scheme: .dark, accent: own, translucent: false).accent == RGBA(hex: 0x12ab9c))
        #expect(AccentColor(rawValue: "purple") == .purple && AccentColor.purple.isCustom == false)
        for bad in ["", "teal", "#12ab9", "12ab9c", "#12ab9z", "#12ab9c0"] { #expect(AccentColor(rawValue: bad) == nil) }
    }

    @Test func the_three_tints_lay_the_accent_over_the_surfaces() {
        let base = themeSurfaces(.forest, scheme: .dark, translucent: false)
        #expect(themeSurfaces(.forest, scheme: .dark, tint: .off, translucent: false) == base)
        for tint in [Tint.subtle, .strong] {
            let tinted = themeSurfaces(.forest, scheme: .dark, tint: tint, translucent: false)
            let accent = base.accent!
            let t = tint.opacity
            #expect(close(tinted.window, RGBA(
                red: base.window.red * (1 - t) + accent.red * t, green: base.window.green * (1 - t) + accent.green * t,
                blue: base.window.blue * (1 - t) + accent.blue * t)))
            #expect(tinted.window != base.window && tinted.sidebar != base.sidebar && tinted.window.alpha == 1)
            #expect(tinted.accent == base.accent)
        }
        #expect(Tint.subtle.opacity < Tint.strong.opacity)
        // the tint is the theme's own color: the accent chosen for the elements changes them and not the windows
        let pink = themeSurfaces(.forest, scheme: .dark, accent: .pink, tint: .strong, translucent: false)
        let own = themeSurfaces(.forest, scheme: .dark, tint: .strong, translucent: false)
        #expect(pink.window == own.window && pink.sidebar == own.sidebar && pink.accent == AccentColor.pink.color)
    }

    @Test func solid_draws_opaque_surfaces_and_translucent_lets_the_sidebar_through() {
        for theme in Theme.allCases.filter({ $0 != .carrier }) {
            let solid = themeSurfaces(theme, scheme: .dark, translucent: false)
            let glass = themeSurfaces(theme, scheme: .dark, translucent: true)
            #expect(solid.sidebar.alpha == 1 && glass.sidebar.alpha < 1)
            #expect(glass.window == solid.window)
            #expect(glass.accent == solid.accent)
        }
    }

    @Test func carrier_leaves_its_surfaces_to_the_system_while_translucent() {
        let glass = themeSurfaces(.carrier, scheme: .light, translucent: true)
        #expect(glass.window == .clear && glass.sidebar == .clear)
        #expect(themeSurfaces(.carrier, scheme: .light, translucent: false).window == RGBA(hex: 0xf2f2f7))
        // a tint on it is the accent alone, at the tint's opacity
        let tinted = themeSurfaces(.carrier, scheme: .light, tint: .strong, translucent: true)
        #expect(close(tinted.window, RGBA(hex: 0x007aff, alpha: Tint.strong.opacity)))
    }

    // MARK: what design/tokens.json says, pinned to the values the code held before it

    /// The `switch` that `Theme.swift` had, copied here before it was deleted: window, sidebar and accent of each theme and version.
    private static let before: [(Theme, ThemeScheme, UInt32, UInt32, UInt32?)] = [
        (.carrier, .dark, 0x1c1c1e, 0x2f2f33, nil), (.carrier, .light, 0xf2f2f7, 0xdcdce2, nil),
        (.graphite, .dark, 0x17181a, 0x26272a, 0x98989d), (.graphite, .light, 0xececee, 0xd9d9dc, 0x636366),
        (.ocean, .dark, 0x0f1b24, 0x18304a, 0x32ade6), (.ocean, .light, 0xeaf3fa, 0xcfe3f2, 0x0a7fc0),
        (.forest, .dark, 0x121a14, 0x1d2f22, 0x30d158), (.forest, .light, 0xeef5ee, 0xd3e6d6, 0x1f9d45),
        (.sunset, .dark, 0x1f1712, 0x34241a, 0xff9f0a), (.sunset, .light, 0xfbf1e6, 0xf1dcc3, 0xd97706),
        (.paper, .dark, 0x222120, 0x32302d, 0x6ea8ff), (.paper, .light, 0xf6f4ef, 0xe6e1d4, 0x007aff),
        (.rose, .dark, 0x1f1418, 0x35212a, 0xff6b9a), (.rose, .light, 0xfbeff2, 0xf2d6de, 0xd6336c),
        (.lavender, .dark, 0x18141f, 0x2a2238, 0xb58cff), (.lavender, .light, 0xf3effb, 0xe0d6f2, 0x7c3aed),
        (.midnight, .dark, 0x0a0e1a, 0x141b30, 0x2dd4bf), (.midnight, .light, 0xeceef8, 0xd3d8ee, 0x0f9d8a),
    ]

    @Test func the_nine_themes_in_both_versions_keep_the_values_of_the_switch_they_came_from() {
        #expect(Theme.allCases.count == 9 && Self.before.count == 18)
        for (theme, scheme, window, sidebar, accent) in Self.before {
            #expect(
                themeSurfaces(theme, scheme: scheme, translucent: false) == ThemeSurfaces(window: RGBA(hex: window), sidebar: RGBA(hex: sidebar), accent: accent.map { RGBA(hex: $0) }),
                "\(theme) \(scheme)")
        }
    }

    @Test func the_seven_presets_keep_their_names_and_values() {
        let before: [(String, UInt32)] = [("blue", 0x0a84ff), ("purple", 0xbf5af2), ("pink", 0xff375f), ("red", 0xff453a), ("orange", 0xff9f0a), ("green", 0x30d158), ("graphite", 0x8e8e93)]
        #expect(AccentColor.allCases.map(\.rawValue) == before.map(\.0))
        for (name, hex) in before { #expect(AccentColor(rawValue: name)?.color == RGBA(hex: hex), "\(name)") }
        #expect([AccentColor.blue, .purple, .pink, .red, .orange, .green, .graphite] == AccentColor.allCases)
    }

    /// A color the views drew from components (0 to 1): a hex holds each of them to within half a step of 255.
    private func matches(_ hex: UInt32, _ red: Double, _ green: Double, _ blue: Double) -> Bool {
        let color = RGBA(hex: hex)
        return [(color.red, red), (color.green, green), (color.blue, blue)].allSatisfy { abs($0 - $1) <= 0.5 / 255 + 1e-9 }
    }

    /// `Color(hue:saturation:brightness:)` as components.
    private func hsb(_ hue: Double, _ saturation: Double, _ brightness: Double) -> (Double, Double, Double) {
        let sector = Int(hue * 6) % 6, fraction = hue * 6 - Double(Int(hue * 6))
        let p = brightness * (1 - saturation), q = brightness * (1 - saturation * fraction), t = brightness * (1 - saturation * (1 - fraction))
        return [(brightness, t, p), (q, brightness, p), (p, brightness, t), (p, q, brightness), (t, p, brightness), (brightness, p, q)][sector]
    }

    @Test func each_semantic_color_keeps_the_value_of_the_literal_it_was_taken_from() {
        // SessionRowView: the orange of "Waiting for you" (the system's on dark), done, the cyan of work in the background
        #expect(matches(Tokens.Status.attention.light, 0.70, 0.36, 0))
        #expect(Tokens.Status.attention.dark == 0xff9f0a && RGBA(hex: Tokens.Status.attention.dark) == AccentColor.orange.color)
        #expect(matches(Tokens.Status.done.light, 0.12, 0.55, 0.24) && matches(Tokens.Status.done.dark, 0.19, 0.70, 0.31))
        #expect(matches(Tokens.Status.background.light, 0.0, 0.48, 0.70) && matches(Tokens.Status.background.dark, 0.35, 0.78, 0.98))
        // SessionPeekView: the violet of work in hand; ChatToolGroupView: the slow call is the orange of "Waiting for you"
        #expect(matches(Tokens.Status.working.light, 0.42, 0.22, 0.72) && matches(Tokens.Status.working.dark, 0.79, 0.63, 1.0))
        #expect(Tokens.Status.slowCall.light == Tokens.Status.attention.light && Tokens.Status.slowCall.dark == Tokens.Status.attention.dark)
        // ChatToolGroupView: the kinds of tool call (`Color.thought` is the dark violet)
        #expect(matches(Tokens.ToolCall.thought.light, 0.48, 0.29, 0.75) && matches(Tokens.ToolCall.thought.dark, 0.79, 0.63, 1.0))
        #expect(matches(Tokens.ToolCall.files.light, 0.04, 0.39, 0.78) && matches(Tokens.ToolCall.files.dark, 0.42, 0.71, 1.0))
        #expect(matches(Tokens.ToolCall.shell.light, 0.11, 0.54, 0.24) && matches(Tokens.ToolCall.shell.dark, 0.31, 0.85, 0.45))
        #expect(matches(Tokens.ToolCall.mcp.light, 0.66, 0.39, 0.0) && matches(Tokens.ToolCall.mcp.dark, 1.0, 0.70, 0.25))
        #expect(matches(Tokens.ToolCall.subagents.light, 0.54, 0.18, 0.75) && matches(Tokens.ToolCall.subagents.dark, 0.84, 0.55, 1.0))
        // ChatApprovalView: the dusty amber, the same in both versions
        let amber = hsb(0.07, 0.5, 0.78)
        #expect(matches(Tokens.Attention.approval.light, amber.0, amber.1, amber.2) && Tokens.Attention.approval.light == Tokens.Attention.approval.dark)
        // The Mac's accent, which a tint over Carrier's own surfaces uses, and ToolbarPillButton's glass and selected row
        #expect(Tokens.Accent.system.light == 0x007aff && Tokens.Accent.system.dark == 0x0a84ff)
        #expect(Tokens.Accent.glass.light == AccentShade(darken: 0.4, alpha: 1) && Tokens.Accent.glass.dark == AccentShade(darken: 0.4, alpha: 1))
        #expect(Tokens.Accent.selectedRow.light == AccentShade(darken: 0, alpha: 0.45))
        #expect(Tokens.Accent.selectedRow.dark == AccentShade(darken: 0.5, alpha: 0.85))
        // SettingsSidebar: the terminal page's tile, `Color(white: 0.25)`; ProjectTileIcon: the eight muted hues of a project's tile, the same in both versions
        #expect(matches(Tokens.Tile.terminal.light, 0.25, 0.25, 0.25) && Tokens.Tile.terminal.light == Tokens.Tile.terminal.dark)
        let projectColors: [(SchemePair<UInt32>, (Double, Double, Double))] = [
            (Tokens.ProjectColor.red, hsb(0.98, 0.56, 0.64)), (Tokens.ProjectColor.orange, hsb(0.06, 0.60, 0.62)),
            (Tokens.ProjectColor.yellow, hsb(0.125, 0.56, 0.52)), (Tokens.ProjectColor.green, hsb(0.375, 0.54, 0.51)),
            (Tokens.ProjectColor.teal, hsb(0.47, 0.54, 0.52)), (Tokens.ProjectColor.blue, hsb(0.61, 0.56, 0.64)),
            (Tokens.ProjectColor.purple, hsb(0.76, 0.52, 0.64)), (Tokens.ProjectColor.pink, hsb(0.90, 0.52, 0.64)),
        ]
        for (pair, rgb) in projectColors { #expect(matches(pair.light, rgb.0, rgb.1, rgb.2) && pair.light == pair.dark) }
    }
}
