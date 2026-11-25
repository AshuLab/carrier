import CarrierCore
import SwiftUI

/// A line of a page that says what went wrong in its words, in orange, and says it to VoiceOver when it appears or changes (`announces`).
/// `size` is for a place that wants another size than the page's 12 pt, scaled by the text size.
public struct ProblemLine: View {
    let text: String
    /// The base size, scaled by the text size.
    var size: CGFloat = 12
    var announces = true

    public init(text: String, size: CGFloat = 12, announces: Bool = true) { self.text = text; self.size = size; self.announces = announces }

    public var body: some View {
        Label(text, icon: .warningFilled)
            .scaledFont(size)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
            .onAppear { if announces { AccessibilityNotification.Announcement(text).post() } }
            .onChange(of: text) { _, text in if announces { AccessibilityNotification.Announcement(text).post() } }
    }
}
