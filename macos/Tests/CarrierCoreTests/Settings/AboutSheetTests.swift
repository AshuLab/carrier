import Foundation
import Testing
@testable import CarrierCore

@Test func theThreeLinksAreWebURLs() {
    #expect(aboutLinks.map(\.title) == ["Release notes", "Documentation", "GitHub"])
    for link in aboutLinks { #expect(browserURL(link.url.absoluteString) == link.url && link.url.scheme == "https") }
}
