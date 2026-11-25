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
    defaults.set("lucide", forKey: Preference.appearanceIconSet.name)
    defaults.set(2.25, forKey: Preference.appearanceIconWeight.name)
    #expect(IconSet.stored(in: defaults) == .lucide && IconWeight.stored(in: defaults) == 2.25)
    // a set that is not one of ours, and a weight past the range
    defaults.set("phosphor", forKey: Preference.appearanceIconSet.name)
    defaults.set(7.0, forKey: Preference.appearanceIconWeight.name)
    #expect(IconSet.stored(in: defaults) == .tabler && IconWeight.stored(in: defaults) == IconWeight.range.upperBound)
}

@Test func resetOfAppearanceTakesTheSetAndTheWeightBackToTheirDefaults() throws {
    let defaults = try #require(UserDefaults(suiteName: "icons-reset-\(UUID().uuidString)"))
    defaults.set("sfSymbols", forKey: Preference.appearanceIconSet.name)
    defaults.set(2.0, forKey: Preference.appearanceIconWeight.name)
    AppPreferences(defaults: defaults).reset(.appearance)
    #expect(IconSet.stored(in: defaults) == IconSet.defaultSet && IconWeight.stored(in: defaults) == IconWeight.defaultWeight)
}

@Test func everyBundledSVGStillDecodesAtEveryWeightAfterItsRewrite() throws {
    for set in [IconSet.tabler, .lucide] {
        for icon in AppIcon.allCases {
            guard case .svg(_, _, let fill) = iconAsset(icon, in: set), let url = iconAsset(icon, in: set).url else { Issue.record("\(set) \(icon)"); continue }
            let svg = try String(contentsOf: url, encoding: .utf8)
            for weight in [IconWeight.range.lowerBound, IconWeight.defaultWeight, IconWeight.range.upperBound] {
                let image = NSImage(data: Data(IconWeight.svg(svg, weight: weight, fill: fill).utf8))
                #expect(image != nil && (image?.size.width ?? 0) > 0, Comment(rawValue: "\(set) \(icon) at \(weight)"))
            }
        }
    }
}

@Test func theWeightPicksTheFontWeightOfASymbolSevenWaysAndTheDefaultIsTheRegularOne() {
    #expect(IconWeight.symbolStep(IconWeight.range.lowerBound) == 0 && IconWeight.symbolStep(IconWeight.range.upperBound) == 6)
    #expect(IconWeight.symbolStep(IconWeight.defaultWeight) == 2)
    let steps = stride(from: IconWeight.range.lowerBound, through: IconWeight.range.upperBound, by: IconWeight.step).map(IconWeight.symbolStep)
    #expect(steps == steps.sorted() && Set(steps).count == 7)
}

@Test func lucideFillsOnlyTheIconsWhoseOutlineIsAClosedShape() {
    // filling a path that is open (the microphone's stand) closes it and swallows the shape: those stay outlines
    let filled = AppIcon.allCases.filter { icon in if case .svg(_, _, true) = iconAsset(icon, in: .lucide) { true } else { false } }
    #expect(Set(filled) == [.circleFilled, .pauseFilled, .pinFilled, .playFilled, .starFilled, .stopFilled])
    #expect(iconAsset(.microphoneFilled, in: .lucide) == .svg(folder: "LucideIcons", name: "mic", fill: false))
}
