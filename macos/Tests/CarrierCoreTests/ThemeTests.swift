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
        // the tint follows the accent that was chosen
        let pink = themeSurfaces(.forest, scheme: .dark, accent: .pink, tint: .strong, translucent: false)
        #expect(pink.window.red > themeSurfaces(.forest, scheme: .dark, tint: .strong, translucent: false).window.red)
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
}
