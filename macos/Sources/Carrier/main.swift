import AppKit

// Plain AppKit lifecycle, no SwiftUI App scenes: a scene that is not inserted can end the app on its own.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// an app of the Dock and the menu bar, with its menu item at the right of the screen besides
app.setActivationPolicy(.regular)
app.run()
