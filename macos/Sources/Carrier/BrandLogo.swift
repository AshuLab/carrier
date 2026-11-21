import CarrierCore
import SwiftUI

/// The logo over the sidebar's title bar: the mark and, beside it, the name when the bar has room (`brandShowsName`, from the column's width and whether
/// the update shows). With the name it starts after the safe zone kept for the window's buttons; without it the mark is centred in the bar. It is an
/// overlay at an exact place and not a toolbar item, because the toolbar moves its items as the room changes and put the logo under the buttons. Two
/// one-colour templates that take the text's colour in light and in dark, each at its own size.
struct BrandLogo: View {
    let sidebarWidth: Double
    private let model = AppUpdater.model
    static let height: CGFloat = 18
    /// The window's title bar, where the pill and the buttons are centred.
    static let barHeight: CGFloat = 52
    @MainActor private static var images: [BrandPart: NSImage] = [:]

    var body: some View {
        let mark = Self.image(.mark), name = Self.image(.name)
        let shows = brandShowsName(
            sidebarWidth: sidebarWidth, updateShown: model.flow.phase != .none, markWidth: Self.width(of: mark), nameWidth: Self.width(of: name))
        ZStack {
            if shows {
                HStack(spacing: 0) {
                    piece(mark)
                    piece(name)
                }
                .padding(.leading, brandSafeZone).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                piece(mark)
            }
        }
        .frame(maxWidth: .infinity).frame(height: Self.barHeight)
        .animation(.easeOut(duration: 0.15), value: shows)
        .accessibilityElement(children: .ignore).accessibilityLabel("Carrier")
    }

    private func piece(_ image: NSImage) -> some View {
        Image(nsImage: image).renderingMode(.template).resizable()
            .frame(width: Self.width(of: image), height: Self.height).foregroundStyle(.primary)
    }

    /// The width a piece takes at the logo's height, from the proportions of its own drawing, so a new export of either needs no change here.
    private static func width(of image: NSImage) -> CGFloat {
        image.size.height > 0 ? height * image.size.width / image.size.height : 0
    }

    @MainActor private static func image(_ part: BrandPart) -> NSImage {
        if let known = images[part] { return known }
        let image = brandURL(part).flatMap { NSImage(contentsOf: $0) } ?? NSImage()
        image.isTemplate = true
        images[part] = image
        return image
    }
}
