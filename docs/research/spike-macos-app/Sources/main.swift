import AppKit

// CA mode: a plain AppKit lifecycle (status item + NSMenu + an NSWindow hosting SwiftUI), no SwiftUI App scenes that could
// terminate the app. Everything else keeps the SwiftUI App used by the other spike modes and by --render.
if Store.ca && !CommandLine.arguments.contains("--render") {
    let app = NSApplication.shared
    let delegate = CAAppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
} else {
    SpikeApp.main()
}
