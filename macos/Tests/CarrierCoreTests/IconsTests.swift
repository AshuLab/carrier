import AppKit
import Foundation
import Testing
@testable import CarrierCore

@Test(arguments: IconSet.allCases)
func everyIconIsInEverySetWithItsFileOrItsSymbol(set: IconSet) throws {
    for icon in AppIcon.allCases {
        switch iconAsset(icon, in: set) {
        case .symbol(let name):
            #expect(set == .sfSymbols && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, Comment(rawValue: "\(icon) → \(name)"))
        case .svg(let folder, let name, let fill):
            let url = try #require(iconAsset(icon, in: set).url, Comment(rawValue: "\(set) \(icon): \(folder)/\(name)"))
            let svg = try String(contentsOf: url, encoding: .utf8)
            // a filled file is drawn by its fill; an outline by its stroke, which the weight rewrites (and `fill` fills)
            let filledFile = folder.hasSuffix("/filled")
            #expect(svg.contains(filledFile ? "fill=\"currentColor\"" : "stroke-width=\"2\""), Comment(rawValue: "\(set) \(icon)"))
            #expect(fill == false || filledFile == false, Comment(rawValue: "\(set) \(icon) fills a file that is filled already"))
        }
    }
}

@Test func theSetsThatAreBundledCarryTheirLicencesNextToTheirIcons() throws {
    let tabler = try #require(carrierResources.url(forResource: "LICENSE", withExtension: nil, subdirectory: "TablerIcons"))
    #expect(try String(contentsOf: tabler, encoding: .utf8).hasPrefix("MIT License\n\nCopyright (c) 2020-2024 Paweł Kuna"))
    let lucide = try #require(carrierResources.url(forResource: "LICENSE", withExtension: nil, subdirectory: "LucideIcons"))
    #expect(try String(contentsOf: lucide, encoding: .utf8).hasPrefix("ISC License"))
}

@Test func aSolidIconIsFilledWhereTheSetHasItFilledAndOtherwiseDrawnFilledOrAsAnOutline() {
    #expect(AppIcon.allCases.filter(\.isSolid).count == 4)
    // Tabler has a filled file of each; Lucide fills the shapes that stay readable filled and keeps the others as outlines
    #expect(iconAsset(.playFilled, in: .tabler) == .svg(folder: "TablerIcons/filled", name: "player-play", fill: false))
    #expect(iconAsset(.playFilled, in: .lucide) == .svg(folder: "LucideIcons", name: "play", fill: true))
    #expect(iconAsset(.warningFilled, in: .lucide) == .svg(folder: "LucideIcons", name: "triangle-alert", fill: false))
    #expect(iconAsset(.check, in: .sfSymbols) == .symbol("checkmark"))
}

@Test func theWeightRewritesTheStrokeOfAnOutlineAndStaysInsideItsRange() throws {
    let check = try String(contentsOf: #require(iconAsset(.check, in: .tabler).url), encoding: .utf8)
    #expect(IconWeight.svg(check, weight: 1.5).contains("stroke-width=\"1.5\""))
    #expect(IconWeight.svg(check, weight: 9).contains("stroke-width=\"2.5\""))
    #expect(IconWeight.svg(check, weight: 0).contains("stroke-width=\"1.0\""))
    let filled = try String(contentsOf: #require(iconAsset(.checkCircleFilled, in: .tabler).url), encoding: .utf8)
    #expect(IconWeight.svg(filled, weight: 1.5) == filled)
}

@Test func fillingAnOutlineChangesItsFillAndKeepsItsStroke() throws {
    let play = try String(contentsOf: #require(iconAsset(.playFilled, in: .lucide).url), encoding: .utf8)
    #expect(play.contains("fill=\"none\""))
    let solid = IconWeight.svg(play, weight: 1.5, fill: true)
    #expect(solid.contains("fill=\"currentColor\"") && !solid.contains("fill=\"none\"") && solid.contains("stroke-width=\"1.5\""))
}

@Test func theSavedSetAndWeightAreReadWithTheirDefaults() throws {
    let defaults = try #require(UserDefaults(suiteName: "icons-\(UUID().uuidString)"))
    #expect(IconSet.stored(in: defaults) == .tabler && IconWeight.stored(in: defaults) == 1.5)
    defaults.set("lucide", forKey: IconSet.key)
    defaults.set(2.25, forKey: IconWeight.key)
    #expect(IconSet.stored(in: defaults) == .lucide && IconWeight.stored(in: defaults) == 2.25)
    // a set that is not one of ours, and a weight past the range
    defaults.set("phosphor", forKey: IconSet.key)
    defaults.set(7.0, forKey: IconWeight.key)
    #expect(IconSet.stored(in: defaults) == .tabler && IconWeight.stored(in: defaults) == IconWeight.range.upperBound)
}

@Test func resetOfAppearanceTakesTheSetAndTheWeightBackToTheirDefaults() throws {
    let defaults = try #require(UserDefaults(suiteName: "icons-reset-\(UUID().uuidString)"))
    defaults.set("sfSymbols", forKey: IconSet.key)
    defaults.set(2.0, forKey: IconWeight.key)
    AppPreferences(defaults: defaults).reset(.appearance)
    #expect(IconSet.stored(in: defaults) == IconSet.defaultSet && IconWeight.stored(in: defaults) == IconWeight.defaultWeight)
}
