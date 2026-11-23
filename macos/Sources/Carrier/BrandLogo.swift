import CarrierCore
import SwiftUI

/// The logo over the sidebar's title bar: the mark alone, centred in the bar. It is an overlay at an exact place and not a toolbar item, because the
/// toolbar moves its items as the room changes and put the logo under the window's buttons. A one-colour template that takes the text's colour in light
/// and in dark.
struct BrandLogo: View {
    static let height: CGFloat = 18
    /// The window's title bar, where the pill and the buttons are centred.
    static let barHeight: CGFloat = 52
    @MainActor private static var mark: NSImage = {
        let image = brandMarkURL().flatMap { NSImage(contentsOf: $0) } ?? NSImage()
        image.isTemplate = true
        return image
    }()

    var body: some View {
        let image = Self.mark
        Image(nsImage: image).renderingMode(.template).resizable()
            .frame(width: Self.width(of: image), height: Self.height).foregroundStyle(.primary)
            .frame(maxWidth: .infinity).frame(height: Self.barHeight)
            .accessibilityElement(children: .ignore).accessibilityLabel("Carrier")
    }

    /// The width at the logo's height, from the proportions of its own drawing, so a new export needs no change here.
    private static func width(of image: NSImage) -> CGFloat {
        image.size.height > 0 ? height * image.size.width / image.size.height : 0
    }
}
