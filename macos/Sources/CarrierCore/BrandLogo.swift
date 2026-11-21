import Foundation

/// The logo of Carrier (`Resources/Brand`) in two pieces, one-colour SVGs drawn as templates so they take the colour of the text: the mark, which is always
/// where it is, and the name, which is left out when there is no room for it.
public enum BrandPart: String, Equatable {
    case mark = "carrier-mark"
    case name = "carrier-wordmark"
}

public func brandURL(_ part: BrandPart) -> URL? {
    carrierResources.url(forResource: part.rawValue, withExtension: "svg", subdirectory: "Brand")
}

/// The room kept at the left of the sidebar's title bar for the window's buttons: nothing of the logo is drawn in it.
public let brandSafeZone = 96.0

/// Whether the sidebar's title bar has room for the name beside the mark: what is left of the column after the safe zone, the mark, the margins (12 and
/// 12) and, while an update shows, its pill (about 120). The widths are those of the two pieces as drawn. Without room the mark is centred in the bar.
public func brandShowsName(sidebarWidth: Double, updateShown: Bool, markWidth: Double, nameWidth: Double) -> Bool {
    sidebarWidth - (brandSafeZone + markWidth + 12 + 12 + (updateShown ? 120 : 0)) >= nameWidth
}
