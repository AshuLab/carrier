import AppKit
import CarrierCore
import SwiftUI

/// A text with links: the pointing hand over each one, and the chip lighter under the pointer. `Text` says nothing of where a run was drawn
/// (a text renderer is never called for selectable text), so the links are placed by laying the same text out again with TextKit at the
/// width the view has: same font, same line spacing, same breaks. ponytail: a font or a break that TextKit sets a little differently from
/// SwiftUI moves a link's hit area by a few points; an NSTextView would be exact if that is ever noticed.
struct LinkedText: View {
    let text: AttributedString
    @Environment(\.colorScheme) private var scheme
    @State private var places: [(link: Int, rect: CGRect)] = []
    @State private var hovered: Int?
    @State private var overLink = false
    @State private var width: CGFloat = 0
    @AppStorage(Preference.chatTextSize) private var size
    @AppStorage(Preference.chatLineSpacing) private var spacing

    var body: some View {
        Text(lit)
            // no `contentTransition(.interpolate)` here: interpolating a text whose runs have a background (the chips) leaves ghost rectangles of
            // them over the other lines while the lit link fades, so the chip changes at once
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0; replace() }
            .onChange(of: text) { places = [] }
            // a size or a spacing moves the lines without always changing the width, so the places are laid out again here
            .onChange(of: size) { replace() }
            .onChange(of: spacing) { replace() }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let hit = places.first { $0.rect.contains(point) }?.link
                    set(hit)
                case .ended: set(nil)
                }
            }
            .onDisappear { set(nil) }
    }

    private func replace() { places = Self.place(links: text, width: width, size: ChatText.clamped(CGFloat(size)), spacing: spacing) }

    /// The text with the link under the pointer in a stronger tint.
    private var lit: AttributedString {
        guard let hovered else { return text }
        var out = text
        var index = 0
        for run in text.runs where run.link != nil {
            if index == hovered { out[run.range].backgroundColor = Color.themeAccent.opacity(scheme == .dark ? 0.45 : 0.3) }
            index += 1
        }
        return out
    }

    private func set(_ link: Int?) {
        hovered = link
        guard (link != nil) != overLink else { return }
        overLink = link != nil
        if overLink { NSCursor.pointingHand.push() } else { NSCursor.pop() }
    }

    /// The rectangles each link takes (one per line it spans), numbered in the order the links come, in the text's own coordinates.
    private static func place(links text: AttributedString, width: CGFloat, size: CGFloat, spacing: ChatLineSpacing) -> [(link: Int, rect: CGRect)] {
        guard width > 0 else { return [] }
        let base = NSFont.chat(size)
        let ns = NSMutableAttributedString()
        var ranges: [NSRange] = []
        for run in text.runs {
            let piece = String(text[run.range].characters)
            var font = base
            if run.font != nil {
                font = .chat(size * 6 / 13) // the short empty line
            } else if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) { font = .chat(size, mono: true) }
                if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
            }
            if run.link != nil { ranges.append(NSRange(location: ns.length, length: piece.utf16.count)) }
            ns.append(NSAttributedString(string: piece, attributes: [.font: font]))
        }
        let style = NSMutableParagraphStyle()
        style.lineSpacing = spacing.extra(forSize: size)
        ns.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: ns.length))
        let storage = NSTextStorage(attributedString: ns)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        var found: [(link: Int, rect: CGRect)] = []
        for (index, range) in ranges.enumerated() {
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layout.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                found.append((index, rect))
            }
        }
        return found
    }
}
