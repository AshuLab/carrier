import AppKit
import SwiftUI

extension View {
    /// Invokes `action` when the user clicks the middle mouse button (scroll wheel button) inside this view.
    func onMiddleClick(perform action: @escaping () -> Void) -> some View {
        background(MiddleClickRepresentable(action: action).allowsHitTesting(false))
    }
}

private struct MiddleClickRepresentable: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MiddleClickMonitorView {
        let view = MiddleClickMonitorView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: MiddleClickMonitorView, context: Context) {
        nsView.action = action
    }

    static func dismantleNSView(_ nsView: MiddleClickMonitorView, coordinator: ()) {
        nsView.removeMonitor()
    }
}

/// Transparent background AppKit view that observes middle-button (`buttonNumber == 2`) press/release within its visible bounds
/// without interfering with SwiftUI left-clicks, hover tracking, context menus, or drag-and-drop.
@MainActor
final class MiddleClickMonitorView: NSView {
    static let middleButtonNumber = 2

    var action: () -> Void = {}
    private var pressedInside = false
    nonisolated(unsafe) private var monitor: Any?

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            removeMonitor()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp]) { [weak self] event in
            guard let self else { return event }
            return handleMouseEvent(event)
        }
    }

    func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        pressedInside = false
    }

    /// Processes a mouse event for this view; returns `nil` when consumed.
    @discardableResult
    func handleMouseEvent(_ event: NSEvent) -> NSEvent? {
        let consumed = handleMiddleButtonEvent(
            type: event.type,
            buttonNumber: event.buttonNumber,
            locationInWindow: event.locationInWindow,
            eventWindow: event.window
        )
        return consumed ? nil : event
    }

    /// Evaluates a mouse transition against this view's visible window bounds; exposed internally so tests can drive events deterministically.
    @discardableResult
    func handleMiddleButtonEvent(
        type: NSEvent.EventType,
        buttonNumber: Int,
        locationInWindow: NSPoint,
        eventWindow: NSWindow?
    ) -> Bool {
        guard buttonNumber == Self.middleButtonNumber else { return false }
        guard let window, eventWindow === window else {
            if type == .otherMouseUp { pressedInside = false }
            return false
        }
        guard isHiddenOrHasHiddenAncestor == false else {
            pressedInside = false
            return false
        }

        let localPoint = convert(locationInWindow, from: nil)
        let insideVisibleBounds = visibleRect.isEmpty == false && visibleRect.contains(localPoint)

        switch type {
        case .otherMouseDown:
            pressedInside = insideVisibleBounds
            return false
        case .otherMouseUp:
            let shouldFire = pressedInside && insideVisibleBounds
            pressedInside = false
            guard shouldFire else { return false }
            let handler = action
            DispatchQueue.main.async {
                handler()
            }
            return true
        default:
            return false
        }
    }
}
