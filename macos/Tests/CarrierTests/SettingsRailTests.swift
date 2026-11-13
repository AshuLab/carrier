import AppKit
import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

@Test @MainActor func theRailDrawsTheAppGroupWithNoHeadingThenCarrierThenLegacyWithTheirHeadings() {
    let sections = SettingsRail.sections
    #expect(sections.map(\.group.heading) == [nil, "Carrier", "Legacy"])
    // Dictation is in the App group right after Chat, whatever else the group holds
    let app = sections[0].pages
    #expect(app.first == .general && app.last == .updates)
    #expect(app.firstIndex(of: .dictation) == app.firstIndex(of: .chat).map { $0 + 1 })
    #expect(sections[1].pages == [.providers, .repos, .agents, .behavior, .engine])
    #expect(sections[2].pages == [.sessions, .health])
    // and the view is built from them
    let renderer = ImageRenderer(content: SettingsRail(page: .constant(.general)).frame(height: 700))
    #expect(renderer.cgImage != nil)
}
