import CarrierCore
import CarrierUI
import SwiftUI

/// The Icons of `CarrierUI/` in the states their catalog entries list.
struct PiecesGalleryIcons: View {
    @Environment(\.pieceTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s22) {
            GalleryEntry("Glyph", "IconImages") {
                GalleryState(.normal) { HStack(spacing: Tokens.Space.s10) { ForEach(PiecesGalleryData.icons, id: \.self) { Glyph($0) } } }
                GalleryState(.large) { HStack(spacing: Tokens.Space.s10) { ForEach(PiecesGalleryData.icons, id: \.self) { Glyph($0, size: 26) } } }
                GalleryState(.bold) { HStack(spacing: Tokens.Space.s10) { ForEach(PiecesGalleryData.icons, id: \.self) { Glyph($0, size: 26, bold: true) } } }
                GalleryState(.working) { Glyph(.refresh, size: 20).glyphSpinning(true) }
                GalleryState(.sets) {
                    // the same icon in each set, as the images the AppKit that draws an icon itself asks for
                    HStack(spacing: Tokens.Space.s14) {
                        ForEach(IconSet.allCases, id: \.self) { set in
                            VStack(spacing: Tokens.Space.s3) {
                                Image(nsImage: IconImages.image(.search, set: set, weight: theme.iconWeight, bold: false, pointSize: 26)).renderingMode(.template).resizable().scaledToFit().frame(width: 26, height: 26)
                                Text(set.title()).scaledFont(10).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            GalleryEntry("AccountMark") {
                GalleryState(.symbol) { AccountMark(symbol: PiecesGalleryData.symbol, tint: .purple, size: 22) }
                GalleryState(.initials) { AccountMark(initials: PiecesGalleryData.initials, tint: .blue, size: 22) }
                GalleryState(.tool) { AccountMark(tool: "claude", size: 22) }
            }
            GalleryEntry("BrandLogo") {
                GalleryState(.normal) { BrandLogo().frame(width: 220) }
            }
            GalleryEntry("CardChevron") {
                GalleryState(.folded) { CardChevron(open: false) }
                GalleryState(.open) { CardChevron(open: true) }
            }
            GalleryEntry("Disc") {
                GalleryState(.normal) { Disc(color: .green, mark: "✓", symbol: .checkCircleFilled) }
                GalleryState(.byShape) { Disc(color: .green, mark: "✓", symbol: .checkCircleFilled).modifier(ByShape()) }
            }
            GalleryEntry("ProjectIcon") {
                GalleryState(.initials) { ProjectIcon(initials: PiecesGalleryData.initials, color: ProjectIcon.palette[0]) }
                GalleryState(.symbol) { ProjectIcon(initials: "", color: ProjectIcon.palette[7], mark: .code) }
                GalleryState(.image) { ProjectIcon(initials: "", color: ProjectIcon.palette[3], image: NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)) }
                GalleryState(.working) { ProjectIcon(initials: PiecesGalleryData.initials, color: ProjectIcon.palette[12], working: true) }
                GalleryState(.waiting) { ProjectIcon(initials: PiecesGalleryData.initials, color: ProjectIcon.palette[12], working: true, background: true) }
                GalleryState(.finished) { ProjectIcon(initials: PiecesGalleryData.initials, color: ProjectIcon.palette[12], finished: true) }
            }
            GalleryEntry("ProviderMark") {
                GalleryState(.normal) { HStack(spacing: Tokens.Space.s10) { ForEach(PiecesGalleryData.tools, id: \.self) { ProviderMark(name: $0, size: 22) } } }
                GalleryState(.empty) { ProviderMark(name: PiecesGalleryData.unknownTool, size: 22) }
            }
            GalleryEntry("StateGlyph") {
                GalleryState(.working) { StateGlyph(look: .ring, label: sample(.label)) }
                GalleryState(.done) { StateGlyph(look: .disc(color: .green, mark: "✓", symbol: .checkCircleFilled), label: sample(.label)) }
                GalleryState(.error) { StateGlyph(look: .disc(color: .orange, mark: "!", symbol: .warningFilled), label: sample(.label)) }
                GalleryState(.waiting) { StateGlyph(look: .hollow, label: sample(.label)) }
            }
            GalleryEntry("StateMark") {
                GalleryState(.normal) { StateMark(text: "!", symbol: .warningFilled, size: 14).foregroundStyle(.orange) }
                GalleryState(.byShape) { StateMark(text: "!", symbol: .warningFilled, size: 14).foregroundStyle(.orange).modifier(ByShape()) }
            }
            GalleryEntry("StatusMark") {
                GalleryState(.done) { StatusMark(symbol: .check, color: .green, label: sample(.label)) }
                GalleryState(.warning) { StatusMark(symbol: .exclamation, color: .yellow, label: sample(.label)) }
                GalleryState(.failed) { StatusMark(symbol: .close, color: .orange, label: sample(.label)) }
            }
        }
    }
}

/// "Tell states apart by shape" on, for the states that wear their symbol then.
private struct ByShape: ViewModifier {
    @Environment(\.pieceTheme) private var theme

    func body(content: Content) -> some View {
        var shaped = theme
        shaped.statesByShape = true
        return content.environment(\.pieceTheme, shaped)
    }
}
