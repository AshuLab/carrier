import CarrierCore
import SwiftUI

/// The Selects of `Carrier/UI/` in the states their catalog entries list.
struct PiecesGallerySelects: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            GalleryEntry("SelectMenu", "ChoicePopUp") {
                GalleryState(.normal) { MenuSample(disabled: false) }
                GalleryState(.disabled) { MenuSample(disabled: true) }
            }
            GalleryEntry("SegmentedChoice") {
                GalleryState(.normal) { SegmentSample(icons: false) }
                GalleryState(.withIcon) { SegmentSample(icons: true) }
            }
            GalleryEntry("SelectButtonStyle", "SelectChevron") {
                GalleryState(.normal) { select(disabled: false) }
                GalleryState(.disabled) { select(disabled: true) }
            }
        }
    }

    private func select(disabled: Bool) -> some View {
        Button {} label: { HStack(spacing: 6) { Text(sample(.label)); SelectChevron() } }.buttonStyle(SelectButtonStyle()).disabled(disabled)
    }
}

/// The choices of a select are the caller's, and so is the one chosen.
private func choices() -> [(value: Int, title: String)] { [(0, sample(.choiceOne)), (1, sample(.choiceTwo)), (2, sample(.choiceThree))] }

private struct MenuSample: View {
    let disabled: Bool
    @State private var index = 0
    @State private var value = 0

    var body: some View {
        HStack(spacing: 16) {
            SelectMenu(items: choices().map(\.title), selection: $index)
            ChoicePopUp(label: sample(.label), options: choices(), selection: $value)
        }
        .disabled(disabled)
    }
}

private struct SegmentSample: View {
    let icons: Bool
    @State private var value = 0

    var body: some View {
        let marks: [AppIcon] = [.code, .clock, .archive]
        SegmentedChoice(options: choices().map { (value: $0.value, title: $0.title, icon: icons ? marks[$0.value] : nil) }, selection: $value)
    }
}
