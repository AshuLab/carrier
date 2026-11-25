import AppKit
import CarrierCore
import SwiftUI

extension DictationWidgetLook {
    /// The window's size: the Pill's, or the box's at the person's text size.
    var windowSize: CGSize {
        guard let box else { return Self.pillSize }
        return CGSize(width: box.width, height: box.height(textSize: TypeScale.stored().size(box.text)))
    }

    /// The Pill is a capsule and a box has the message box's radius.
    var radius: CGFloat { box == nil ? windowSize.height / 2 : 16 }
    var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
}

/// The widget's glass, by the theme: the chat's surface tinted with the app's accent (a light veil of it over a light window and a dark one over a dark window
/// so the text reads over a white window too), a solid black, dark glass, the system's glass with no tint, or the colours of the listening line as glass. A soft shadow
/// goes with all of them, since the panel has none of its own.
struct WidgetSurface: ViewModifier {
    let shape: RoundedRectangle
    var theme = DictationWidgetTheme.accent
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        switch theme {
        case .accent:
            let tint = scheme == .dark ? Color.themeAccent.mix(with: .black, by: 0.6).opacity(0.55) : Color.themeAccent.opacity(0.12)
            content.chatSurface(.regular.tint(tint), flat: tint, in: shape).shadow(color: .black.opacity(0.22), radius: 10, y: 3)
        case .black:
            content.chatSurface(.regular.tint(.black.opacity(0.92)), flat: .black.opacity(0.92), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        case .glassDark:
            content.chatSurface(.regular.tint(.black.opacity(0.4)), flat: .black.opacity(0.55), in: shape).shadow(color: .black.opacity(0.28), radius: 10, y: 3)
        case .clear:
            // the system's glass as it is, with no tint: its text follows the system's appearance
            content.chatSurface(.regular, in: shape).shadow(color: .black.opacity(0.2), radius: 10, y: 3)
        case .glow:
            // the colours of the listening line (the accent and its two neighbouring hues) laid side to side as the surface, over dark glass: a gradient from one edge to the other
            let colors = DictationIndicator.accentColors()
            let wash = LinearGradient(colors: [colors[2], colors[0], colors[1]], startPoint: .leading, endPoint: .trailing)
            content
                .background(shape.fill(wash).opacity(0.6))
                .chatSurface(.regular.tint(.black.opacity(0.2)), flat: .black.opacity(0.5), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.22), lineWidth: 1))
                .shadow(color: colors[0].opacity(0.4), radius: 9, y: 2)
        }
    }
}

/// A box of the widget: the text at the top, a row under it, and when the text is longer than the lines of the style it scrolls so the newest words
/// are on the last line, with the older lines fading out at the top (`dictationTextFit`). A `follows: false` box (the text that was only copied)
/// starts at the top and is the person's to scroll, with no fade and with its scroll bar showing, under the `notices` (a reason, in orange), which
/// stay where they are.
struct WidgetBox<Content: View, Foot: View>: View {
    let box: DictationWidgetBox
    var follows = true
    var notices: [String] = []
    @ViewBuilder var text: Content
    @ViewBuilder var foot: Foot
    @State private var position = ScrollPosition(edge: .top)
    @State private var textLines = 0
    @Environment(\.textScale) private var textScale

    var body: some View {
        let lineHeight = box.lineHeight(textSize: textScale.size(box.text))
        let fadesTop = follows && dictationTextFit(textLines: textLines, boxLines: box.lines).fadesTop
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            if notices.isEmpty == false {
                VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                    ForEach(notices, id: \.self) { Text($0).foregroundStyle(.orange) }
                }
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            if box.showsText {
                ScrollView {
                    text.frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(follows ? .hidden : .visible)
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, height in
                    guard follows else { return }
                    textLines = Int((height / lineHeight).rounded())
                    if dictationTextFit(textLines: textLines, boxLines: box.lines).fadesTop { position.scrollTo(edge: .bottom) }
                }
                .mask {
                    VStack(spacing: Tokens.Space.none) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: fadesTop ? lineHeight : 0)
                        Rectangle()
                    }
                }
            }
            HStack { foot }.font(.scaled(11)).foregroundStyle(.secondary).frame(height: 20)
        }
        .font(.scaled(box.text))
        .padding(.horizontal, Tokens.Space.s16).padding(.vertical, Tokens.Space.s12)
    }
}
