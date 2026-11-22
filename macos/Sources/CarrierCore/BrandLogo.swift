import Foundation

/// The mark of Carrier (`Resources/Brand`), a one-colour SVG drawn as a template so it takes the colour of the text.
public func brandMarkURL() -> URL? {
    carrierResources.url(forResource: "carrier-mark", withExtension: "svg", subdirectory: "Brand")
}
