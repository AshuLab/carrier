import AppKit
import CarrierCore
import SwiftUI

/// The mark of a provider, as the rest of the app draws it (its bundled icon in the text colour, its letter when it has none).
public struct ProviderMark: View {
    let name: String
    var size: CGFloat = 14

    public init(name: String, size: CGFloat = 14) { self.name = name; self.size = size }
    @MainActor private static var images: [String: NSImage] = [:]

    public var body: some View {
        if let image = Self.image(name) {
            Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Text(String(name.prefix(1)).uppercased()).scaledFont(size * 0.8, weight: .bold).frame(width: size, height: size)
        }
    }

    /// The bundled icon of the provider `harness`, as a template, nil when it has none.
    @MainActor public static func image(_ harness: String) -> NSImage? {
        if let known = images[harness] { return known }
        guard let url = providerIconURL(harness), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        images[harness] = image
        return image
    }
}
