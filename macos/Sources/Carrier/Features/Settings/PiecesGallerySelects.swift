import CarrierCore
import CarrierUI
import SwiftUI

/// The Selects of `CarrierUI/` in the states their catalog entries list.
struct PiecesGallerySelects: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s22) {
            GalleryEntry("SelectMenu", "ChoicePopUp") {
                GalleryState(.normal) { MenuSample(disabled: false) }
                GalleryState(.disabled) { MenuSample(disabled: true) }
            }
            GalleryEntry("SegmentedChoice") {
                GalleryState(.normal) { SegmentSample(icons: false) }
                GalleryState(.withIcon) { SegmentSample(icons: true) }
            }
            GalleryEntry("ThemeGallery") {
                GalleryState(.normal) { ThemeGallerySample(count: Theme.allCases.count, chosen: 1) }
                GalleryState(.long) { ThemeGallerySample(count: 40, chosen: 0) }
                GalleryState(.atEnd) { ThemeGallerySample(count: 40, chosen: 39) }
            }
            GalleryEntry("SelectButtonStyle", "SelectChevron") {
                GalleryState(.normal) { select(disabled: false) }
                GalleryState(.disabled) { select(disabled: true) }
            }
        }
    }

    private func select(disabled: Bool) -> some View {
        Button {} label: { HStack(spacing: Tokens.Space.s6) { Text(sample(.label)); SelectChevron() } }.buttonStyle(SelectButtonStyle()).disabled(disabled)
    }
}

/// The choices of a select are the caller's, and so is the one chosen.
private func choices() -> [(value: Int, title: String)] { [(0, sample(.choiceOne)), (1, sample(.choiceTwo)), (2, sample(.choiceThree))] }

private struct MenuSample: View {
    let disabled: Bool
    @State private var index = 0
    @State private var value = 0

    var body: some View {
        HStack(spacing: Tokens.Space.s16) {
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

private struct ThemeGallerySample: View {
    let count: Int
    @State private var chosen: Int

    init(count: Int, chosen: Int) {
        self.count = count
        self._chosen = State(initialValue: chosen)
    }

    var body: some View {
        let cells = PiecesGalleryData.themeCells(count: count)
        // wider than a column of states, so three columns and half of the next one are not squeezed
        ThemeGallery(cells: cells, chosen: cells[chosen].id) { id in chosen = cells.firstIndex { $0.id == id } ?? chosen }.frame(width: 640)
    }
}
