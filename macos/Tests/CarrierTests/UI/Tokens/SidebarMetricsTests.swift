import AppKit
import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

extension TextSizeInTheDefaults {
    @MainActor @Test func theSidebarTypeIsTodaysAtAHundredPercent() {
        UserDefaults.standard.removeObject(forKey: "appearance.textSize")
        #expect(TypeScale().font(SidebarMetrics.Level.section.base, weight: SidebarMetrics.Level.section.weight) == Font.system(size: 16, weight: .medium))
        #expect(TypeScale().font(SidebarMetrics.Level.group.base, weight: SidebarMetrics.Level.group.weight) == Font.system(size: 12, weight: .semibold))
        #expect(TypeScale().font(SidebarMetrics.Level.item.base, weight: SidebarMetrics.Level.item.weight) == Font.system(size: 14))
        #expect(TypeScale().font(SidebarMetrics.Level.detail.base, weight: SidebarMetrics.Level.detail.weight) == Font.system(size: 12))
        #expect(CommandTextView.font.pointSize == 14)
        #expect(CommandTextView.lineHeight == 22)
    }
}
