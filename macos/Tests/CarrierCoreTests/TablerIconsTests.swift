import Foundation
import Testing
@testable import CarrierCore

@Test func everyIconTheAppNamesHasItsSVGAndTheLicenceTravelsWithThem() throws {
    for icon in TablerIcon.allCases {
        let url = try #require(icon.url, Comment(rawValue: icon.rawValue))
        let svg = try String(contentsOf: url, encoding: .utf8)
        // an outline is drawn by its stroke, which the weight setting rewrites; a filled icon by its fill, which it leaves alone
        #expect(svg.contains(icon.isFilled ? "fill=\"currentColor\"" : "stroke-width=\"2\""), Comment(rawValue: icon.rawValue))
    }
    let licence = try #require(carrierResources.url(forResource: "LICENSE", withExtension: nil, subdirectory: "TablerIcons"))
    #expect(try String(contentsOf: licence, encoding: .utf8).hasPrefix("MIT License\n\nCopyright (c) 2020-2024 Paweł Kuna"))
}

@Test func noTwoIconsAreTheSameFile() {
    #expect(Set(TablerIcon.allCases.map(\.rawValue)).count == TablerIcon.allCases.count)
}

@Test func theWeightRewritesTheStrokeOfAnOutlineAndStaysInsideItsRange() throws {
    let check = try String(contentsOf: #require(TablerIcon.check.url), encoding: .utf8)
    #expect(IconWeight.svg(check, weight: 1.5).contains("stroke-width=\"1.5\""))
    #expect(IconWeight.svg(check, weight: 9).contains("stroke-width=\"2.5\""))
    #expect(IconWeight.svg(check, weight: 0).contains("stroke-width=\"1.0\""))
    let star = try String(contentsOf: #require(TablerIcon.checkCircleFilled.url), encoding: .utf8)
    #expect(IconWeight.svg(star, weight: 1.5) == star)
}

@Test func theSavedWeightIsReadInsideItsRangeAndDefaultsToOneAndAHalf() throws {
    let defaults = try #require(UserDefaults(suiteName: "icon-weight-\(UUID().uuidString)"))
    #expect(IconWeight.stored(in: defaults) == 1.5)
    defaults.set(2.25, forKey: IconWeight.key)
    #expect(IconWeight.stored(in: defaults) == 2.25)
    defaults.set(7.0, forKey: IconWeight.key)
    #expect(IconWeight.stored(in: defaults) == IconWeight.range.upperBound)
}

@Test func resetOfAppearanceTakesTheWeightBackToItsDefault() throws {
    let defaults = try #require(UserDefaults(suiteName: "icon-weight-reset-\(UUID().uuidString)"))
    let preferences = AppPreferences(defaults: defaults)
    defaults.set(2.0, forKey: IconWeight.key)
    preferences.reset(.appearance)
    #expect(IconWeight.stored(in: defaults) == IconWeight.defaultWeight)
}
