import CarrierCore
import SwiftUI

/// The logo over the sidebar's title bar: the mark alone, centred in the bar. It is an overlay at an exact place and not a toolbar item, because the
/// toolbar moves its items as the room changes and put the logo under the window's buttons. A one-colour template that takes the text's colour in light
/// and in dark. A dev build ("Carrier Dev") draws it in the pink of its Dock icon and puts a DEV MODE badge after it, so it is told from the installed one at a glance.
public struct BrandLogo: View {

    public init() {}
    public static let height: CGFloat = 18
    /// The window's title bar, where the pill and the buttons are centred.
    static let barHeight: CGFloat = 52
    @MainActor private static var mark: NSImage = {
        let image = brandMarkURL().flatMap { NSImage(contentsOf: $0) } ?? NSImage()
        image.isTemplate = true
        return image
    }()

    /// The pink of the dev app's Dock icon (`AppIconDev.icon`).
    private static let devPink = Color(.displayP3, red: 0.96921, green: 0.15760, blue: 0.85935)

    public var body: some View {
        let image = Self.mark
        let mark = Image(nsImage: image).renderingMode(.template).resizable()
            .frame(width: Self.width(of: image), height: Self.height).foregroundStyle(isDevBuild ? Self.devPink : .primary)
        Group {
            if isDevBuild {
                // the badge goes when the sidebar is too narrow for both: the pink mark still says it
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Tokens.Space.s8) { mark; badge }
                    mark
                }
            } else {
                mark
            }
        }
        .frame(maxWidth: .infinity).frame(height: Self.barHeight)
        .accessibilityElement(children: .ignore).accessibilityLabel(isDevBuild ? Copy.pieceBrandDevelopment() : Copy.appName())
    }

    private var badge: some View {
        Text(Copy.pieceDevMode()).scaledFont(10, weight: .bold).tracking(0.8).foregroundStyle(Self.devPink).lineLimit(1)
            .padding(.horizontal, Tokens.Space.s8).padding(.vertical, Tokens.Space.s1)
            .background(Capsule().fill(Self.devPink.opacity(0.14)))
            .overlay(Capsule().strokeBorder(Self.devPink.opacity(0.4), lineWidth: 1))
    }

    /// The width at the logo's height, from the proportions of its own drawing, so a new export needs no change here.
    private static func width(of image: NSImage) -> CGFloat {
        image.size.height > 0 ? height * image.size.width / image.size.height : 0
    }
}
