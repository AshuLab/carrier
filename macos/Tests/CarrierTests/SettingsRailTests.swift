import AppKit
import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

@Test @MainActor func theRailDrawsTheAppGroupWithNoHeadingThenCarrierThenLegacyWithTheirHeadings() {
    let sections = SettingsRail.sections
    #expect(sections.map(\.group.heading) == [nil, "Carrier", "Legacy"])
    #expect(sections[0].pages == [.general, .notifications, .appearance, .sidebar, .chat, .keybindings, .updates])
    #expect(sections[1].pages == [.providers, .repos, .agents, .behavior])
    #expect(sections[2].pages == [.engine, .sessions, .health])
    // and the view is built from them
    let renderer = ImageRenderer(content: SettingsRail(page: .constant(.general)).frame(height: 700))
    #expect(renderer.cgImage != nil)
}
