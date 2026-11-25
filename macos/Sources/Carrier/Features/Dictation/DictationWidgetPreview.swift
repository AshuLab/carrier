import AppKit
import CarrierCore
import SwiftUI

/// The chosen style as the Dictation page shows it, listening to a sample.
struct DictationWidgetPreview: View {
    let style: DictationWidgetStyle
    let theme: DictationWidgetTheme
    let livePreview: Bool
    let hint: String
    /// The width the page gives it, so the Large box (540) shrinks to fit a narrow window instead of overflowing the card.
    @State private var available = CGFloat.infinity
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let look = dictationWidgetLook(.listening, style: style, livePreview: livePreview)
        let scale = min(1, available / look.windowSize.width)
        Group {
            if let box = look.box {
                WidgetBox(box: box) { Text(Copy.dictationWidgetPreviewSample()) } foot: {
                    Text("0:12").monospacedDigit()
                    Spacer()
                    Text(hint)
                }
            } else {
                PillIcon(icon: .mic)
            }
        }
        .frame(width: look.windowSize.width, height: look.windowSize.height)
        .modifier(WidgetSurface(shape: look.shape, theme: theme))
        .environment(\.colorScheme, theme.appearance.map { $0 == .light ? ColorScheme.light : .dark } ?? colorScheme)
        .scaleEffect(scale)
        .frame(width: look.windowSize.width * scale, height: look.windowSize.height * scale)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { available = $0 }
        .accessibilityElement(children: .ignore).accessibilityLabel(Copy.dictationWidgetPreviewLabel(style: style.title(), theme: theme.title()))
    }
}
