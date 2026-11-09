import SwiftUI
import Testing
@testable import CarrierCore
@testable import Carrier

@MainActor @Suite struct MessageTimeLabelTests {
    private func pixels(_ mode: MessageTimes, hovering: Bool) -> Data? {
        let label = MessageTimeLabel(ms: 1_700_000_000_000, mode: mode, hovering: hovering).frame(width: 120, height: 24).background(Color.white)
        let renderer = ImageRenderer(content: label)
        return renderer.nsImage?.tiffRepresentation
    }

    // On hover the time is there only while the pointer is over the message; always it is there, and never it is not.
    @Test func theTimeShowsOnHoverAndOnlyThen() throws {
        let hidden = try #require(pixels(.hover, hovering: false))
        let shown = try #require(pixels(.hover, hovering: true))
        #expect(hidden != shown)
        // not hovering draws what never does, a blank
        #expect(hidden == pixels(.never, hovering: true))
        #expect(shown == pixels(.always, hovering: false))
    }
}
