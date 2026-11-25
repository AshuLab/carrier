import Foundation
import Testing
@testable import CarrierCore

@Test func theThreeLinksAreWebURLs() {
    let links = aboutLinks(bundle: english.bundle, locale: english.locale)
    #expect(links.map(\.title) == ["Release notes", "Documentation", "GitHub"])
    for link in links { #expect(browserURL(link.url.absoluteString) == link.url && link.url.scheme == "https") }
}

@Test func theLinksReadInSpanishWithTheSameAddresses() {
    let links = aboutLinks(bundle: spanish.bundle, locale: spanish.locale)
    #expect(links.map(\.title) == ["Notas de la versión", "Documentación", "GitHub"])
    #expect(links.map(\.url) == aboutLinks(bundle: english.bundle, locale: english.locale).map(\.url))
}
