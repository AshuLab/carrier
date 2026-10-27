import AppKit
import SwiftUI

// Opens the prototype in a window shaped like the app's (a NavigationSplitView in an NSHostingController).
//   swift run                 just the window
//   swift run SpikeSidebar --probe [--variant section]
//                             clicks through the five things from code, prints what happened, exits
// The probe finds each control through the accessibility tree (what VoiceOver sees) and sends it real mouse events.

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
let variant = args.drop { $0 != "--variant" }.dropFirst().first ?? "row"

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let model = SpikeModel()
let host = NSHostingController(rootView: NavigationSplitView {
    SpikeSidebar(model: model, variant: variant)
} detail: { SpikeDetail(model: model) })
host.sceneBridgingOptions = .all
host.sizingOptions = []
let window = NSWindow(contentViewController: host)
window.title = "Sidebar spike"
window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
window.setContentSize(NSSize(width: 1100, height: 700))
window.center()
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

/// What the app's `--smoke-window` prints for the columns: the width of each arranged subview of every split view.
func columns() -> [String] {
    var lines: [String] = []
    func walk(_ view: NSView) {
        if let split = view as? NSSplitView {
            for column in split.arrangedSubviews where column.frame.width > 0 {
                lines.append("column: x \(Int(column.frame.minX.rounded())) width \(Int(column.frame.width.rounded()))")
            }
        }
        view.subviews.forEach(walk)
    }
    if let content = window.contentView { walk(content) }
    return lines
}

if args.contains("--probe") {
    DispatchQueue.main.async { Probe().run() }
}
app.run()
