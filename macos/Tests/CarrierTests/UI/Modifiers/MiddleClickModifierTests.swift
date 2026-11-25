import AppKit
@testable import CarrierUI
import CoreGraphics
import SwiftUI
import Testing
@testable import Carrier

@MainActor
struct MiddleClickModifierTests {
    @Test func firesActionOnlyOnMiddleButtonPressAndReleaseInsideVisibleBounds() async throws {
        var fires = 0
        let content = Color.clear
            .frame(width: 120, height: 32)
            .onMiddleClick { fires += 1 }
        let host = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: host)
        window.setContentSize(NSSize(width: 240, height: 120))
        window.makeKeyAndOrderFront(nil)
        host.view.layoutSubtreeIfNeeded()
        defer { window.close() }

        func findMonitorView(in view: NSView) -> MiddleClickMonitorView? {
            if let target = view as? MiddleClickMonitorView { return target }
            for sub in view.subviews {
                if let found = findMonitorView(in: sub) { return found }
            }
            return nil
        }

        let monitorView = try #require(findMonitorView(in: host.view))
        let insidePoint = monitorView.convert(NSPoint(x: monitorView.bounds.midX, y: monitorView.bounds.midY), to: nil)
        let outsidePoint = NSPoint(
            x: monitorView.convert(NSPoint(x: monitorView.bounds.maxX + 40, y: monitorView.bounds.midY), to: nil).x,
            y: insidePoint.y
        )

        // Verify CGEvent center button maps to MiddleClickMonitorView.middleButtonNumber (2).
        let cgDown = try #require(CGEvent(
            mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center
        ))
        let nsCenterDown = try #require(NSEvent(cgEvent: cgDown))
        #expect(nsCenterDown.buttonNumber == MiddleClickMonitorView.middleButtonNumber)

        // Overlay transparency: normal AppKit hit testing must pass straight through.
        #expect(monitorView.hitTest(NSPoint(x: monitorView.bounds.midX, y: monitorView.bounds.midY)) == nil)

        // 1. Middle button press + release inside fires once and consumes mouseUp.
        #expect(monitorView.handleMiddleButtonEvent(
            type: .otherMouseDown, buttonNumber: MiddleClickMonitorView.middleButtonNumber, locationInWindow: insidePoint, eventWindow: window
        ) == false)
        #expect(monitorView.handleMiddleButtonEvent(
            type: .otherMouseUp, buttonNumber: MiddleClickMonitorView.middleButtonNumber, locationInWindow: insidePoint, eventWindow: window
        ) == true)
        await Task.yield()
        #expect(fires == 1)

        // 2. Side mouse button (buttonNumber 3) does not trigger middle-click action.
        #expect(monitorView.handleMiddleButtonEvent(
            type: .otherMouseDown, buttonNumber: 3, locationInWindow: insidePoint, eventWindow: window
        ) == false)
        #expect(monitorView.handleMiddleButtonEvent(
            type: .otherMouseUp, buttonNumber: 3, locationInWindow: insidePoint, eventWindow: window
        ) == false)
        await Task.yield()
        #expect(fires == 1)

        // 3. Press inside + release outside cancels instead of closing accidentally.
        #expect(monitorView.handleMiddleButtonEvent(
            type: .otherMouseDown, buttonNumber: MiddleClickMonitorView.middleButtonNumber, locationInWindow: insidePoint, eventWindow: window
        ) == false)
        #expect(monitorView.handleMiddleButtonEvent(
            type: .otherMouseUp, buttonNumber: MiddleClickMonitorView.middleButtonNumber, locationInWindow: outsidePoint, eventWindow: window
        ) == false)
        await Task.yield()
        #expect(fires == 1)

        // 4. Press outside + release inside also does not fire.
        #expect(monitorView.handleMiddleButtonEvent(
            type: .otherMouseDown, buttonNumber: MiddleClickMonitorView.middleButtonNumber, locationInWindow: outsidePoint, eventWindow: window
        ) == false)
        #expect(monitorView.handleMiddleButtonEvent(
            type: .otherMouseUp, buttonNumber: MiddleClickMonitorView.middleButtonNumber, locationInWindow: insidePoint, eventWindow: window
        ) == false)
        await Task.yield()
        #expect(fires == 1)

        // 5. Event targeting another window is ignored.
        let otherWindow = NSWindow()
        #expect(monitorView.handleMiddleButtonEvent(
            type: .otherMouseDown, buttonNumber: MiddleClickMonitorView.middleButtonNumber, locationInWindow: insidePoint, eventWindow: otherWindow
        ) == false)
        #expect(monitorView.handleMiddleButtonEvent(
            type: .otherMouseUp, buttonNumber: MiddleClickMonitorView.middleButtonNumber, locationInWindow: insidePoint, eventWindow: otherWindow
        ) == false)
        await Task.yield()
        #expect(fires == 1)

        // 6. Hidden monitor view ignores middle clicks.
        monitorView.isHidden = true
        #expect(monitorView.handleMiddleButtonEvent(
            type: .otherMouseDown, buttonNumber: MiddleClickMonitorView.middleButtonNumber, locationInWindow: insidePoint, eventWindow: window
        ) == false)
        #expect(monitorView.handleMiddleButtonEvent(
            type: .otherMouseUp, buttonNumber: MiddleClickMonitorView.middleButtonNumber, locationInWindow: insidePoint, eventWindow: window
        ) == false)
        await Task.yield()
        #expect(fires == 1)
    }
}
