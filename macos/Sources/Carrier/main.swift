import AppKit

// Plain AppKit lifecycle, no SwiftUI App scenes: a scene that is not inserted can end the app on its own.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
