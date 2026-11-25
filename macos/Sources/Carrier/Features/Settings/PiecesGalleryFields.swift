import CarrierCore
import SwiftUI

/// The Fields of `Carrier/UI/` in the states their catalog entries list.
struct PiecesGalleryFields: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s22) {
            GalleryEntry("NumberField") {
                GalleryState(.normal) { NumberSample() }
                GalleryState(.error) { NumberSample().environment(\.settingsInvalid, true) }
            }
            GalleryEntry("SettingsField") {
                GalleryState(.empty) { FieldSample(text: "", icon: nil) }
                GalleryState(.normal) { FieldSample(text: sample(.field), icon: nil) }
                GalleryState(.withIcon) { FieldSample(text: sample(.query), icon: .search) }
                GalleryState(.error) { FieldSample(text: sample(.field), icon: nil).environment(\.settingsInvalid, true) }
            }
            GalleryEntry("SidebarSearchField") {
                GalleryState(.empty) { SidebarSearchSample(text: "") }
                GalleryState(.normal) { SidebarSearchSample(text: sample(.query)) }
            }
            GalleryEntry("SidebarEmptyBlock", "SidebarNoResults") {
                GalleryState(.empty) { SidebarEmptyBlock(icon: .archive, title: sample(.title), line: sample(.detail)) { EmptyView() }.frame(width: 240) }
                GalleryState(.withActions) {
                    SidebarEmptyBlock(icon: .archive, title: sample(.title), line: sample(.detail)) { Button(sample(.action)) {}.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small) }
                        .frame(width: 240)
                }
                GalleryState(.noResults) { SidebarNoResults(icon: .search, title: sample(.title), line: sample(.query), clear: {}).frame(width: 240) }
            }
        }
    }
}

/// `NumberField` keeps its value and its unparsable keys with the caller.
private struct NumberSample: View {
    @State private var value = PiecesGalleryData.number
    @State private var unparsable: Set<String> = []

    var body: some View {
        NumberField(
            key: sample(.field), value: $value, unparsable: $unparsable, parse: { Int($0) }, format: { String($0) },
            step: { current, direction in current + direction >= 0 ? current + direction : nil }
        )
    }
}

/// `settingsField` goes on a `TextField` the caller owns.
private struct FieldSample: View {
    @State var text: String
    let icon: AppIcon?

    var body: some View {
        TextField(sample(.placeholder), text: $text).settingsField(width: 220, icon: icon)
    }
}

private struct SidebarSearchSample: View {
    @State var text: String
    @FocusState private var focused: Bool

    var body: some View {
        SidebarSearchField(placeholder: sample(.placeholder), text: $text, focus: $focused, close: {}).frame(width: 240)
    }
}
