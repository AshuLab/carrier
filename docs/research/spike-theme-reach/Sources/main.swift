import AppKit
import SwiftUI

// The prototype: a window shaped like the app's (NavigationSplitView in an NSHostingController) with the controls the Appearance
// settings would have to reach, turned by flags.
//   swift run SpikeThemeReach [--theme carrier|forest|sunset] [--scheme light|dark|system] [--scheme-api swiftui|nsapp]
//       [--tint off|subtle|strong] [--no-paint] [--window-bg] [--sheet] [--popover] [--sheet-bg] [--sheet-tint]
//       [--no-accent] [--accent-color-api] [--list-tint] [--row-bg] [--under-title] [--shot out.png]
// With --shot it waits a moment, saves the window as a PNG and quits.

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
func value(_ flag: String) -> String? { args.drop { $0 != flag }.dropFirst().first }

let model = SpikeModel()
model.setting.theme = SpikeTheme.named(value("--theme") ?? "carrier")
model.setting.scheme = value("--scheme") ?? "light"
model.setting.tint = ["subtle": 0.06, "strong": 0.14][value("--tint") ?? ""] ?? 0
model.setting.paint = !args.contains("--no-paint")
model.setting.sheetBackground = args.contains("--sheet-bg")
model.setting.sheetTint = args.contains("--sheet-tint")
model.setting.noAccent = args.contains("--no-accent")
model.setting.accentColorAPI = args.contains("--accent-color-api")
model.setting.listTint = args.contains("--list-tint")
model.setting.underTitle = args.contains("--under-title")
model.setting.rowBackground = args.contains("--row-bg")

let app = NSApplication.shared
app.setActivationPolicy(.regular)
model.setting.schemeNSApp = value("--scheme-api") == "nsapp"
if model.setting.schemeNSApp {
    // the scheme through AppKit: every window, sheet and popover of the app
    app.appearance = switch model.setting.scheme { case "dark": NSAppearance(named: .darkAqua); case "light": NSAppearance(named: .aqua); default: nil }
}
let host = NSHostingController(rootView: SpikeRoot(model: model))
host.sceneBridgingOptions = .all
host.sizingOptions = []
let window = NSWindow(contentViewController: host)
window.title = "Theme reach spike"
window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
window.setContentSize(NSSize(width: 1000, height: 640))
window.center()
if args.contains("--window-bg") {
    // the window's own background: what shows behind everything the app does not paint
    let s = model.setting
    window.backgroundColor = NSColor(s.theme.window(s.dark))
}
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
    if args.contains("--sheet") { model.sheet = true }
    if args.contains("--popover") { model.popover = true }
}
if let out = value("--shot") {
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
        let ok = savePNG(window: window, to: out, withChildren: args.contains("--sheet") || args.contains("--popover"))
        print("shot \(ok ? "saved" : "FAILED") \(out)")
        exit(0)
    }
}
app.run()
