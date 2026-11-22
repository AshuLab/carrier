import Foundation
import Testing

@testable import CarrierCore

@Test func theMarkIsInTheResourceBundleAsPathsOnly() throws {
    let svg = try String(contentsOf: try #require(brandMarkURL()), encoding: .utf8)
    // what the system's SVG renderer draws well: no filter, mask, style, text or image inside
    for word in ["<filter", "<mask", "<style", "<text", "<image", "<rect"] { #expect(svg.contains(word) == false) }
    #expect(svg.contains("<path"))
}
