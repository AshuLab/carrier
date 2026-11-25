import CarrierCore
import SwiftUI

/// A line of a page that says what went wrong in its words, in orange, and says it to VoiceOver when it appears or changes (`announces`).
/// `font` is for a place that wants another size than the page's 12 pt, scaled by the text size.
struct ProblemLine: View {
    let text: String
    var font: Font?
    var announces = true

    var body: some View {
        let line = Label(text, icon: .warningFilled)
        Group {
            if let font { line.font(font) } else { line.scaledFont(12) }
        }
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { if announces { AccessibilityNotification.Announcement(text).post() } }
        .onChange(of: text) { _, text in if announces { AccessibilityNotification.Announcement(text).post() } }
    }
}
