@testable import CarrierCore
import CarrierUI
import SwiftUI
import Testing
@testable import Carrier

@MainActor private func render(_ state: SubagentsButtonState, spoken: String, dark: Bool = false) throws -> (height: Int, bytes: [UInt8]) {
    let view = SubagentsButton(state: state, spoken: spoken, moves: false, action: {})
        .environment(\.colorScheme, dark ? .dark : .light)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    let data = try #require(image.dataProvider?.data)
    let length = CFDataGetLength(data)
    var bytes = [UInt8](repeating: 0, count: length)
    CFDataGetBytes(data, CFRange(location: 0, length: length), &bytes)
    return (image.height, bytes)
}

@MainActor @Test func subagentsButtonMatchesToolbarPillHeightAndDistinguishesEachStateWithoutColourAlone() throws {
    let expectedHeight = Int(ToolbarPillButton.height) * 2
    for dark in [false, true] {
        let running = try render(.running(count: 3), spoken: "3 subagents, 2 running", dark: dark)
        let quietClean = try render(.quiet(total: 3, failed: false), spoken: "3 subagents", dark: dark)
        let quietFailed = try render(.quiet(total: 3, failed: true), spoken: "3 subagents, 1 failed", dark: dark)

        #expect(running.height == expectedHeight)
        #expect(quietClean.height == expectedHeight)
        #expect(quietFailed.height == expectedHeight)
        // the arc on running and the dot on failed each change the rendered pixels independently of colour
        #expect(running.bytes != quietClean.bytes)
        #expect(quietFailed.bytes != quietClean.bytes)
    }
}
