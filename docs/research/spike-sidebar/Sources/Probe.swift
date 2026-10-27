import AppKit

/// Drives the window from code with mouse events sent to the window (no screen-recording or accessibility permission needed:
/// it all happens inside the process). SwiftUI draws no accessibility tree without an assistive client attached, so controls are
/// found in the AppKit views under it: the list is an NSOutlineView whose `ListTableRowView`s are the rows, and every SwiftUI
/// button inside a row shows up as a `KeyViewProxy` with the button's frame.
@MainActor final class Probe {
    private func pause(_ seconds: Double = 0.6) async { try? await Task.sleep(for: .seconds(seconds)) }

    private func all(_ view: NSView, named: String, into found: inout [NSView]) {
        if String(describing: type(of: view)).hasPrefix(named) { found.append(view) }
        view.subviews.forEach { all($0, named: named, into: &found) }
    }

    private func views(_ name: String, in root: NSView? = nil) -> [NSView] {
        var found: [NSView] = []
        if let root = root ?? window.contentView { all(root, named: name, into: &found) }
        return found
    }

    private func frame(_ view: NSView) -> NSRect { view.convert(view.bounds, to: nil) }

    /// The visible rows of the sidebar, top to bottom.
    private func rows() -> [NSView] { views("ListTableRowView").sorted { frame($0).maxY > frame($1).maxY } }

    /// The buttons inside a row, left to right.
    private func buttons(in row: NSView) -> [NSRect] {
        views("KeyViewProxy", in: row).map(frame).sorted { $0.minX < $1.minX }
    }

    private func click(at point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            window.sendEvent(event!)
        }
    }

    /// The Sessions row's search (1), sort (2) and new-session (3) buttons: the last three of the row.
    private func icon(_ n: Int) -> NSRect { let b = buttons(in: rows()[1]); return b[b.count - 4 + n] }

    /// The fold: the chevron button of the row variant; in the section variant the system's own disclosure at the row's left edge.
    private func fold() {
        let row = rows()[1], b = buttons(in: row)
        if b.count == 4 { click(b[0]) } else { click(at: NSPoint(x: frame(row).minX + 10, y: frame(row).midY)) }
    }

    private func click(_ rect: NSRect) { click(at: NSPoint(x: rect.midX, y: rect.midY)) }

    /// A click on the row's label side, away from any button.
    private func clickRow(_ row: NSView) { let f = frame(row); click(at: NSPoint(x: f.minX + 90, y: f.midY)) }

    /// Each open popover and how far its edge is from the middle of the sort button (the one it is anchored to).
    private func popovers() -> [String] {
        let sort = window.convertToScreen(icon(2))
        return NSApp.windows.filter { String(describing: type(of: $0)).contains("Popover") }.map {
            "\(type(of: $0)) \(Int($0.frame.width))x\(Int($0.frame.height)), \(Int(abs($0.frame.minX - sort.maxX))) pt right of the sort button, \(Int(abs($0.frame.midY - sort.midY))) pt off its middle"
        }
    }

    /// The rows that carry the system's selection highlight: an NSVisualEffectView directly under the row view.
    private func highlighted() -> [Int] {
        rows().enumerated().filter { $0.element.subviews.contains { String(describing: type(of: $0)) == "NSVisualEffectView" } }.map(\.offset)
    }

    private func state(_ what: String) {
        print("[\(what)] key=\(window.isKeyWindow) selection=\(model.selection) open=\(String(describing: model.open)) log=\(model.log) search=\(model.searchOpen) sortPopover=\(model.sortPopover) rows=\(rows().count) highlighted rows=\(highlighted()) popovers=\(popovers())")
    }

    func run() {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
            await pause(1.5)
            print("variant \(variant)")
            for (index, row) in rows().enumerated() { print("  row \(index): \(Int(frame(row).height)) high, buttons \(buttons(in: row).map { Int($0.minX) })") }
            state("start")
            for line in columns() { print(line) }
            let sessions = 1

            // the first click only activates the window; it selects nothing
            clickRow(rows()[0]); await pause(0.3)
            for x in [75, 150] {
                let f = frame(rows()[sessions]); click(at: NSPoint(x: f.minX + CGFloat(x), y: f.midY)); await pause(0.3)
                state("click the Sessions row at x+\(x) (label, then empty space)")
                clickRow(rows()[0]); await pause(0.3)
            }
            // 3. a row with icon buttons: clicking one must not select the row
            click(icon(1)); await pause()
            state("click the magnifier of the Sessions row")
            // 4. a popover anchored to one of those buttons
            click(icon(2)); await pause()
            state("click the ... button")
            for popover in NSApp.windows where String(describing: type(of: popover)).contains("Popover") { popover.close() }
            model.sortPopover = false; await pause()
            click(icon(3)); await pause()
            state("click the + button")
            for popover in NSApp.windows where String(describing: type(of: popover)).contains("Popover") { popover.close() }
            model.plusPopover = false; await pause()
            // 2. a fold
            fold(); await pause()
            state("click the chevron (fold)")
            fold(); await pause()
            state("click the chevron (unfold)")
            // 1. the card: opens into a list and folds back
            let card = rows().last { frame($0).height > 60 }!
            clickRow(card); await pause()
            state("click the Carrier card")
            if model.open == .carrier, rows().count > 4 {
                clickRow(rows()[4]); await pause()
                state("click an epic row under the card")
            }
            // 5. one selection across Home, a session, an epic and Settings (a footer outside the list)
            clickRow(rows()[0]); await pause()
            state("click Home")
            let footer = NSPoint(x: 100, y: 28)
            click(at: footer); await pause()
            state("click Settings (footer button)")
            fold(); await pause()
            if model.open == nil { fold(); await pause() }
            clickRow(rows()[3]); await pause()
            state("click a session row (after reopening Sessions)")
            // the AppKit limit the app met with `.inspector`: resize the window and fold sections at the same time, 40 times
            for i in 0..<40 {
                window.setContentSize(NSSize(width: i.isMultiple(of: 2) ? 1400 : 1100, height: 700))
                fold(); await pause(0.05)
            }
            print("resize while folding: survived 40 rounds")
            print("columns at the end:"); for line in columns() { print(line) }
            exit(0)
        }
    }
}
