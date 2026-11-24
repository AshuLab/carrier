import AppKit
import Testing
@testable import Carrier

@Test func theIconsLayerHostTakesNoClicks() {
    let host = PassthroughView(frame: NSRect(x: 0, y: 0, width: 40, height: 24))
    #expect(host.hitTest(NSPoint(x: 10, y: 10)) == nil)
    #expect(host.hitTest(NSPoint(x: -5, y: 50)) == nil)
}
