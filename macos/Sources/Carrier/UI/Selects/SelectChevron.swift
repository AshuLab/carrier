import SwiftUI

/// The chevrons of a select in their small circle, as the Mac's pop-up draws them in a form.
struct SelectChevron: View {
    var body: some View {
        Image(systemName: "chevron.up.chevron.down").scaledFont(8, weight: .bold).foregroundStyle(.primary.opacity(0.85))
            .frame(width: 18, height: 18).background(Circle().fill(Color.primary.opacity(0.12))).accessibilityHidden(true)
    }
}
