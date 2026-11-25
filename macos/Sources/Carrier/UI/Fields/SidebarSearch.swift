import CarrierCore
import SwiftUI

/// The search field of a sidebar section, shared by Sessions and Carrier (and Archive): a row of its own under the section's row,
/// not selectable, with a clear button once it has text. Esc runs `close`; the clear button empties the field and keeps the keyboard in it.
struct SidebarSearchField: View {
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    let close: () -> Void
    @State private var clearHovered = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .focused(focus)
            .onKeyPress(.escape) {
                close()
                return .handled
            }
            .overlay(alignment: .trailing) {
                if text.isEmpty == false {
                    Button {
                        text = ""
                        focus.wrappedValue = true
                    } label: {
                        Glyph(.closeCircleFilled).foregroundStyle(clearHovered ? .primary : .secondary).padding(.trailing, 5)
                    }
                    .buttonStyle(.plain)
                    .onHover { clearHovered = $0 }
                    .help("Clear")
                    .accessibilityLabel("Clear")
                }
            }
    }
}

/// What a section's list says when it has nothing to show: the state's icon and title, a line and, when there is one, a button under them.
struct SidebarEmptyBlock<Action: View>: View {
    let icon: AppIcon
    let title: String
    let line: String
    @ViewBuilder let action: Action

    var body: some View {
        VStack(spacing: 4) {
            Glyph(icon, size: 26).foregroundStyle(.secondary).padding(.bottom, 4)
            Text(title).font(.headline)
            Text(line).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
            action.padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .accessibilityElement(children: .contain)
    }
}

/// What a section's list says when a search matches nothing: the struck magnifier, `No results`, what was typed and a button that
/// empties the field. The area says the words (`SidebarNoResults(query:clear:)`).
struct SidebarNoResults: View {
    let icon: AppIcon
    let title: String
    let line: String
    let clear: () -> Void

    var body: some View {
        SidebarEmptyBlock(icon: icon, title: title, line: line) {
            Button("Clear search", action: clear)
        }
    }
}
