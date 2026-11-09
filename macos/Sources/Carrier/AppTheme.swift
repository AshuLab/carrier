import AppKit
import CarrierCore
import Observation
import SwiftUI

/// The theme in force, for the views to read while they draw (as `TextSize` does): the theme, the accent, the tint and the translucent
/// windows of Settings, the color scheme that is showing and the system's Reduce transparency, all turned into `themeSurfaces`.
@Observable final class AppTheme {
    static let shared = AppTheme()

    private(set) var surfaces = AppTheme.current()
    @ObservationIgnored private var appearance: NSKeyValueObservation?

    private init() {
        let refresh = { [self] in
            let now = Self.current()
            if now != surfaces { surfaces = now }
        }
        // any change of the defaults: what Settings writes, and what Reset removes
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in refresh() }
        // the Mac switching between light and dark while the color scheme is System
        appearance = NSApplication.shared.observe(\.effectiveAppearance) { _, _ in DispatchQueue.main.async { refresh() } }
    }

    private static func current() -> ThemeSurfaces {
        let preferences = AppPreferences()
        let dark = switch preferences.colorScheme {
        case .light: false
        case .dark: true
        case .system: NSApplication.shared.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        return themeSurfaces(
            preferences.theme, scheme: dark ? .dark : .light, accent: preferences.accent, tint: preferences.tint,
            translucent: preferences.translucent(systemReducesTransparency: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        )
    }

    /// The accent of the app's own views: the theme's, or the Mac's while the theme has none.
    var accent: Color { surfaces.accent.map(Color.init) ?? .accentColor }
}

extension Color {
    init(_ color: RGBA) { self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha) }

    /// What the app draws with where it used the system's accent: that one does not follow the theme, this one does.
    static var themeAccent: Color { AppTheme.shared.accent }
}

extension View {
    /// The theme's accent and window color on the root of a window or a sheet. A sheet is another window: it takes neither the accent nor
    /// the color of the window it opens over. Carrier's translucent windows have no color of their own, so the sheet keeps the system's.
    func themed() -> some View {
        let surfaces = AppTheme.shared.surfaces
        return tint(surfaces.accent.map(Color.init))
            .presentationBackground(surfaces.window.alpha > 0 ? AnyShapeStyle(Color(surfaces.window)) : AnyShapeStyle(.background))
    }

    /// The color the theme gives the windows, under the content and under the title bar, where a page that has the toolbar's band hidden
    /// would otherwise show the system's grey.
    func themedWindowBackground() -> some View { background(Color(AppTheme.shared.surfaces.window), ignoresSafeAreaEdges: .all) }

    /// The color the theme gives the sidebar, under the content.
    func themedSidebarBackground() -> some View { background(Color(AppTheme.shared.surfaces.sidebar)) }
}
