@testable import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

@MainActor private func rowHeight(percent: Int?) throws -> Int {
    if let percent { UserDefaults.standard.set(percent, forKey: Preference.appearanceTextSize.name) } else { UserDefaults.standard.removeObject(forKey: Preference.appearanceTextSize.name) }
    defer { UserDefaults.standard.removeObject(forKey: Preference.appearanceTextSize.name) }
    let row = FlowItemView(flow: .note(id: 1, text: "Reading the sources of the slice"), flipped: .constant([]))
    let renderer = ImageRenderer(content: row.frame(width: 400))
    renderer.scale = 2
    return try #require(renderer.cgImage).height
}

/// The tests that write the text size into the standard defaults, one at a time.
@Suite(.serialized) struct TextSizeInTheDefaults {
    // A transcript row takes its font from the type scale: the text size preference makes it taller, and 100 leaves it as it was.
    @MainActor @Test func aTranscriptRowFollowsTheTextSize() throws {
        let normal = try rowHeight(percent: nil)
        #expect(try rowHeight(percent: 100) == normal)
        #expect(try rowHeight(percent: 130) > normal)
        #expect(try rowHeight(percent: 90) < normal)
    }
}
