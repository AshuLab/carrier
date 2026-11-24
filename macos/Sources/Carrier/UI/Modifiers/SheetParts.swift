import CarrierCore
import SwiftUI

private struct WindowSizeKey: EnvironmentKey { static let defaultValue = CGSize(width: 1100, height: 700) }

extension EnvironmentValues {
    /// The main window's size, set by the panel for the sheets over it.
    var windowSize: CGSize {
        get { self[WindowSizeKey.self] }
        set { self[WindowSizeKey.self] = newValue }
    }
}

private struct SheetSized: ViewModifier {
    @Environment(\.windowSize) private var window
    let maxWidth: Double

    func body(content: Content) -> some View {
        let size = sheetSize(windowWidth: window.width, windowHeight: window.height, maxWidth: maxWidth)
        content.frame(width: size.width, height: size.height)
    }
}

extension View {
    /// A sheet of the window's own: three quarters of it, so it grows and shrinks with the window (`sheetSize`), its width capped at `maxWidth`.
    func windowSheetSize(maxWidth: Double = .infinity) -> some View { modifier(SheetSized(maxWidth: maxWidth)) }
}

// What the new-session draft's sheets and controls have in common.

/// How tall a control of the draft is: the ones of the sentence and the selects of the box.
let controlHeight: CGFloat = 28

extension View {
    /// The fill and the edge of a control of the draft, the text's own colour faint so they follow the appearance; a `tint` colours both.
    func controlSurface(tint: Color = .primary) -> some View {
        background(
            RoundedRectangle(cornerRadius: 8).fill(tint.opacity(tint == .primary ? 0.07 : 0.14))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(tint == .primary ? 0.14 : 0.4), lineWidth: 1))
        )
    }
}

/// The mark of the chosen row of a list: a white tick on a disc of the accent colour, so the tick reads on it.
struct ChosenMark: View {
    var body: some View {
        Glyph(.check, size: 9, bold: true).foregroundStyle(.white)
            .frame(width: 18, height: 18).background(Circle().fill(Color.themeAccent))
            .accessibilityElement(children: .ignore).accessibilityLabel("Chosen")
    }
}

/// What a state of a thing is, in a word and an icon, in its colour: indigo is private, green is watched.
struct Badge: View {
    let text: String
    let icon: AppIcon
    let tint: Color

    var body: some View {
        Label(text, icon: icon).font(.caption.weight(.medium)).foregroundStyle(tint)
            .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// What a click on the row under the pointer does, as a small solid pill at its end. It is always laid out and only shown under the
/// pointer, so the row is the same height with or without it.
struct RowHint: View {
    let text: String
    let shown: Bool

    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.white)
            // the deepened accent the title bar's pills have under their white words: the accent itself, a light one, left the word without contrast
            .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(Color.accentGlass))
            .opacity(shown ? 1 : 0).accessibilityHidden(true)
    }
}

/// A row that is a button: it takes a faint fill under the pointer, or `fill` when it is the chosen one.
struct HoverRow<Content: View>: View {
    let action: () -> Void
    var fill: Color?
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            content(hovering && enabled).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 8).fill(fill ?? (hovering && enabled ? Color.secondary.opacity(0.14) : .clear)))
        .onHover { hovering = $0 }
    }
}
