import AppKit
import SwiftUI
import Testing
@testable import Carrier

extension TextSizeInTheDefaults {
    @MainActor @Test func theSidebarTypeIsTodaysAtAHundredPercent() {
        UserDefaults.standard.removeObject(forKey: "appearance.textSize")
        #expect(SidebarMetrics.section == Font.system(size: 16, weight: .medium))
        #expect(SidebarMetrics.group == Font.system(size: 12, weight: .semibold))
        #expect(SidebarMetrics.item == Font.system(size: 14))
        #expect(SidebarMetrics.detail == Font.system(size: 12))
        #expect(CommandTextView.font.pointSize == 14)
        #expect(CommandTextView.lineHeight == 22)
    }
}
