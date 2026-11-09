import AppKit
import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

@Test @MainActor func theRailDrawsTheAppGroupWithNoHeadingThenLegacyWithItsHeadingAndItsFive() {
    let sections = SettingsRail.sections
    #expect(sections.map(\.group.heading) == [nil, "Legacy"])
    #expect(sections[0].pages == [.general, .notifications, .appearance, .sidebar, .chat, .keybindings])
    #expect(sections[1].pages == [.engine, .behavior, .repos, .sessions, .health])
    // and the view is built from them
    let renderer = ImageRenderer(content: SettingsRail(page: .constant(.general)).frame(height: 700))
    #expect(renderer.cgImage != nil)
}
