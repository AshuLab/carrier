import CarrierCore
import SwiftUI

/// The search field of a sidebar section, shared by Sessions and Carrier (and Archive): a row of its own under the section's row,
/// not selectable, with a clear button once it has text. Esc runs `close`; the clear button empties the field and keeps the keyboard in it.
public struct SidebarSearchField: View {
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    let close: () -> Void

    public init(
        placeholder: String,
        text: Binding<String>,
        focus: FocusState<Bool>.Binding,
        close: @escaping () -> Void
    ) {
        self.placeholder = placeholder
        self._text = text
        self.focus = focus
        self.close = close
    }
    @State private var clearHovered = false

    public var body: some View {
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
                        Glyph(.closeCircleFilled).foregroundStyle(clearHovered ? .primary : .secondary).padding(.trailing, Tokens.Space.s5)
                    }
                    .buttonStyle(.plain)
                    .onHover { clearHovered = $0 }
                    .help(Copy.pieceClear())
                    .accessibilityLabel(Copy.pieceClear())
                }
            }
    }
}

/// What a section's list says when it has nothing to show: the state's icon and title, a line and, when there is one, a button under them.
public struct SidebarEmptyBlock<Action: View>: View {
    let icon: AppIcon
    let title: String
    let line: String
    @ViewBuilder let action: Action

    public init(
        icon: AppIcon,
        title: String,
        line: String,
        @ViewBuilder action: () -> Action
    ) {
        self.icon = icon
        self.title = title
        self.line = line
        self.action = action()
    }

    public var body: some View {
        VStack(spacing: Tokens.Space.s4) {
            Glyph(icon, size: 26).foregroundStyle(.secondary).padding(.bottom, Tokens.Space.s4)
            Text(title).font(.headline)
            Text(line).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(3)
            action.padding(.top, Tokens.Space.s4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tokens.Space.s18)
        .accessibilityElement(children: .contain)
    }
}

/// What a section's list says when a search matches nothing: the struck magnifier, `No results`, what was typed and a button that
/// empties the field. The area says the words (`SidebarNoResults(query:clear:)`).
public struct SidebarNoResults: View {
    let icon: AppIcon
    let title: String
    let line: String
    let clear: () -> Void

    public init(icon: AppIcon, title: String, line: String, clear: @escaping () -> Void) { self.icon = icon; self.title = title; self.line = line; self.clear = clear }

    public var body: some View {
        SidebarEmptyBlock(icon: icon, title: title, line: line) {
            Button(Copy.pieceClearSearch(), action: clear)
        }
    }
}
