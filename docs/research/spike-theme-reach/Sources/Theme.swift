import SwiftUI

/// The pure value the spike tries: a theme, a scheme and a tint give surface colors and an accent.
struct SpikeTheme {
    var name: String
    var windowLight: Color, windowDark: Color
    var sidebarLight: Color, sidebarDark: Color
    var accent: Color

    static let carrier = SpikeTheme(name: "carrier", windowLight: Color(white: 0.97), windowDark: Color(white: 0.12),
        sidebarLight: Color(white: 0.93), sidebarDark: Color(white: 0.16), accent: .blue)
    static let forest = SpikeTheme(name: "forest", windowLight: Color(red: 0.93, green: 0.97, blue: 0.93), windowDark: Color(red: 0.07, green: 0.13, blue: 0.09),
        sidebarLight: Color(red: 0.86, green: 0.93, blue: 0.87), sidebarDark: Color(red: 0.10, green: 0.19, blue: 0.13), accent: Color(red: 0.18, green: 0.62, blue: 0.35))
    static let sunset = SpikeTheme(name: "sunset", windowLight: Color(red: 1.0, green: 0.96, blue: 0.92), windowDark: Color(red: 0.16, green: 0.09, blue: 0.08),
        sidebarLight: Color(red: 0.99, green: 0.90, blue: 0.84), sidebarDark: Color(red: 0.23, green: 0.12, blue: 0.10), accent: Color(red: 0.93, green: 0.40, blue: 0.20))

    static func named(_ name: String) -> SpikeTheme { [carrier, forest, sunset].first { $0.name == name } ?? carrier }
    func window(_ dark: Bool) -> Color { dark ? windowDark : windowLight }
    func sidebar(_ dark: Bool) -> Color { dark ? sidebarDark : sidebarLight }
}

/// What the person chose; every field is one knob the spike turns from the command line.
struct SpikeSetting {
    var theme = SpikeTheme.carrier
    var scheme = "light"          // light | dark | system
    var tint = 0.0                // 0 off, 0.06 subtle, 0.14 strong: opacity of the accent laid over a surface
    var paint = true              // false: no surface colors at all (the stock look), to compare
    var sheetBackground = false   // .presentationBackground on the sheet
    var sheetTint = false         // .tint(accent) again inside the sheet and the popover
    var noAccent = false          // no .tint at all: what the controls look like on the system's accent
    var accentColorAPI = false    // the old .accentColor(_) modifier on the root
    var listTint = false          // .listItemTint(.fixed) on the native rows and .tint on the list
    var rowBackground = false     // .listRowBackground on the native rows
    var underTitle = false        // the detail's paint also goes under the title bar (ignoresSafeAreaEdges)
    var schemeNSApp = false       // the scheme set on NSApp.appearance instead of .preferredColorScheme
    var dark: Bool { scheme == "dark" }
}
