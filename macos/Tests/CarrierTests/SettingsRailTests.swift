import AppKit
import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

@Test @MainActor func theRailDrawsTheAppGroupWithNoHeadingThenChatAndCarrierWithTheirHeadings() {
    let sections = SettingsRail.sections
    #expect(sections.map(\.group.heading) == [nil, "Chat", "Carrier", nil])
    #expect(sections[0].pages == [.general, .providers, .notifications, .appearance, .terminal, .keybindings, .dictation])
    #expect(sections[1].pages == [.chat, .sidebar, .sessions])
    #expect(sections[2].pages == [.repos, .agents, .behavior, .engine, .health])
    #expect(sections[3].pages == [.about])
    // and the view is built from them
    let renderer = ImageRenderer(content: SettingsRail(page: .constant(.general)).frame(height: 700))
    #expect(renderer.cgImage != nil)
}
