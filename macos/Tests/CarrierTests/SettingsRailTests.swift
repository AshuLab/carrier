import AppKit
import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

@Test @MainActor func theRailDrawsTheAppGroupWithNoHeadingThenChatCarrierAndLegacyWithTheirHeadings() {
    let sections = SettingsRail.sections
    #expect(sections.map(\.group.heading) == [nil, "Chat", "Carrier", "Legacy"])
    #expect(sections[0].pages == [.general, .providers, .notifications, .appearance, .keybindings, .updates])
    #expect(sections[1].pages == [.chat, .sidebar, .sessions, .dictation])
    #expect(sections[2].pages == [.repos, .agents, .behavior])
    #expect(sections[3].pages == [.engine, .health])
    // and the view is built from them
    let renderer = ImageRenderer(content: SettingsRail(page: .constant(.general)).frame(height: 700))
    #expect(renderer.cgImage != nil)
}
