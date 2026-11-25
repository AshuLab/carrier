import CarrierCore
import SwiftUI

/// A choice among a few words, the one select of the app's rows: the system's own pop-up menu (a `Picker` in the menu style), which in a form is drawn as
/// the Mac draws it, the chosen word at the right with the up and down chevrons in a small circle, and opens the system's menu with its own check. It takes
/// the room of its word: rows no longer give it a width. (AppKit's `NSPopUpButton` in its place drew badly in a form; the SwiftUI picker does not.)
public struct SelectMenu: View {
    let items: [String]
    @Binding var selection: Int

    public init(items: [String], selection: Binding<Int>) { self.items = items; self._selection = selection }
    @Environment(\.settingsForm) private var form

    public var body: some View {
        if form {
            Picker(selection: $selection) {
                ForEach(items.indices, id: \.self) { Text(items[$0]).tag($0) }
            } label: { EmptyView() }
            // no tint of the theme's: the window's own tint reaches the picker and colors it, and the system's is neutral
            .pickerStyle(.menu).labelsHidden().fixedSize().tint(nil)
        } else {
            // outside a form the system draws a pop-up in a box: the same face by hand (the words and the circle), over the same system menu and check
            Menu {
                Picker(selection: $selection) {
                    ForEach(items.indices, id: \.self) { Text(items[$0]).tag($0) }
                } label: { EmptyView() }
                .pickerStyle(.inline).labelsHidden()
            } label: {
                HStack(spacing: Tokens.Space.s6) {
                    Text(items.indices.contains(selection) ? items[selection] : (items.first ?? "")).lineLimit(1)
                    SelectChevron()
                }
            }
            .menuStyle(.button).buttonStyle(SelectButtonStyle()).menuIndicator(.hidden).fixedSize()
        }
    }
}
