import Foundation
import Testing

@testable import CarrierCore

@Test func theNameIsLeftOutWhenTheUpdateTakesTheRoom() {
    // the mark 37 points wide and the name 73, as they are at 18 high
    func shows(_ width: Double, update: Bool) -> Bool { brandShowsName(sidebarWidth: width, updateShown: update, markWidth: 37, nameWidth: 73) }
    // the narrowest sidebar: the name fits with nothing beside it, and not once the update shows
    #expect(shows(SidebarStore.widthRange.lowerBound, update: false))
    #expect(shows(SidebarStore.widthRange.lowerBound, update: true) == false)
    // a wide one has room for both
    #expect(shows(400, update: true))
    // the edge is the room the name needs, exactly
    let edge = brandSafeZone + 37 + 24 + 73
    #expect(shows(edge, update: false) && shows(edge - 1, update: false) == false)
}

@Test func theLogoIsInTheResourceBundleAsTwoPiecesOfPathsOnly() throws {
    for part in [BrandPart.mark, .name] {
        let svg = try String(contentsOf: try #require(brandURL(part)), encoding: .utf8)
        // what the system's SVG renderer draws well: no filter, mask, style, text or image inside
        for word in ["<filter", "<mask", "<style", "<text", "<image", "<rect"] { #expect(svg.contains(word) == false) }
        #expect(svg.contains("<path"))
    }
}
