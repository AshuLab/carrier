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

    func body(content: Content) -> some View {
        let size = sheetSize(windowWidth: window.width, windowHeight: window.height)
        content.frame(width: size.width, height: size.height)
    }
}

extension View {
    /// A sheet of the window's own: three quarters of it, so it grows and shrinks with the window (`sheetSize`).
    func windowSheetSize() -> some View { modifier(SheetSized()) }
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
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            .frame(width: 18, height: 18).background(Circle().fill(Color.accentColor))
            .accessibilityLabel("Chosen")
    }
}

/// What a state of a thing is, in a word and an icon, in its colour: indigo is private, green is watched.
struct Badge: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: icon).font(.caption.weight(.medium)).foregroundStyle(tint)
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
            .padding(.horizontal, 10).padding(.vertical, 3).background(Capsule().fill(Color.accentColor))
            .opacity(shown ? 1 : 0).accessibilityHidden(true)
    }
}

/// The rail of a sheet (the workspace chooser, Settings): the sheet's round mark with its name and a line, then rows made of `RailRow`.
struct RailHeader: View {
    let title: String
    let detail: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(LinearGradient(colors: [.accentColor, .accentColor.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 14)
    }
}

/// One choice of a rail: an icon tile, a title and a line, filled when it is the chosen one.
struct RailRow: View {
    let title: String
    let detail: String
    let icon: String
    let selected: Bool
    var off = false
    let action: () -> Void

    var body: some View {
        HoverRow(action: action, fill: selected ? Color.accentColor.opacity(0.22) : nil) { _ in
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(.medium)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(off ? 2 : 1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .disabled(off)
    }
}

/// The clone action of a repository row: a round glass button with a chevron, shown under the pointer. The row itself is the button.
struct CloneChevron: View {
    let shown: Bool

    var body: some View {
        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.white)
            .frame(width: 26, height: 26).glassEffect(.regular.tint(Color.accentColor), in: .circle)
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
