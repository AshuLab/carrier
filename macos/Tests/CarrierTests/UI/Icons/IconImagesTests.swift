import AppKit
import CarrierCore
@testable import CarrierUI
import SwiftUI
import Testing
@testable import Carrier

@MainActor @Test(arguments: [IconSet.tabler, .lucide])
func everyIconOfAnSVGSetComesAsATemplateImageWithASizeAtEveryWeight(set: IconSet) {
    for icon in AppIcon.allCases {
        for weight in [IconWeight.range.lowerBound, IconWeight.range.upperBound] {
            let image = IconImages.image(icon, set: set, weight: weight)
            #expect(image?.isTemplate == true && (image?.size.width ?? 0) > 0, Comment(rawValue: "\(set) \(icon) at \(weight)"))
        }
    }
}

@MainActor @Test func theSFSymbolsAreDrawnAsTextSoTheyHaveNoImageHere() {
    for icon in AppIcon.allCases { #expect(IconImages.image(icon, set: .sfSymbols, weight: 1.5) == nil) }
}

@MainActor @Test(arguments: IconSet.allCases)
func theImageForAppKitIsNeverEmptyAndATemplateInEverySetAtEveryWeight(set: IconSet) {
    for icon in AppIcon.allCases {
        for (weight, bold) in [(IconWeight.range.lowerBound, false), (IconWeight.defaultWeight, true), (IconWeight.range.upperBound, false)] {
            let image = IconImages.image(icon, set: set, weight: weight, bold: bold)
            #expect(image.size.width > 0 && image.size.height > 0 && image.isTemplate, Comment(rawValue: "\(set) \(icon) at \(weight)"))
        }
    }
}

@MainActor @Test(arguments: IconSet.allCases)
func anInlineImageIsATemplateOfTheSizeOfTheTextForAnSVGAndOfItsPointSizeForASymbol(set: IconSet) {
    for icon in AppIcon.allCases {
        let image = IconImages.inline(icon, side: 11, set: set, weight: IconWeight.defaultWeight)
        #expect(image.isTemplate && image.size.width > 0 && image.size.height > 0, Comment(rawValue: "\(set) \(icon)"))
        if set != .sfSymbols { #expect(image.size == NSSize(width: 11, height: 11), Comment(rawValue: "\(set) \(icon)")) }
    }
}

// On the main actor, like the tests that draw: the first use of AppKit starts its menu system once per process. Started from a thread of
// the pool while a test on the main thread reaches it too, the two wait for each other and the run hangs until the watchdog cuts it.
@MainActor @Test func theSystemTakesTheSFSymbolOfEveryIconWhateverTheSetIs() {
    for icon in AppIcon.allCases {
        #expect(NSImage(systemSymbolName: icon.systemSymbolName, accessibilityDescription: nil) != nil, Comment(rawValue: "\(icon)"))
        #expect(iconAsset(icon, in: .sfSymbols) == .symbol(icon.systemSymbolName))
    }
    #expect(AppIcon.folder.systemSymbolName == "folder")
}

@MainActor @Test func aTintedImageKeepsItsAspectInsideTheSquareItIsGiven() throws {
    let wide = NSImage(size: NSSize(width: 20, height: 10), flipped: false) { rect in NSColor.black.setFill(); rect.fill(); return true }
    let tinted = wide.tinted(.white, size: NSSize(width: 24, height: 24))
    #expect(tinted.size == NSSize(width: 24, height: 24))
    let data = try #require(tinted.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: data))
    // 20 x 10 fitted in 24 x 24 is 24 x 12: the top and bottom thirds are empty, the middle is white
    #expect(bitmap.colorAt(x: 12, y: 2)?.alphaComponent == 0)
    #expect((bitmap.colorAt(x: 12, y: 12)?.alphaComponent ?? 0) > 0.9)
}

@Test func theSymbolWeightFollowsTheStrokeWeightInSevenSteps() {
    #expect(Font.Weight(strokeWeight: IconWeight.defaultWeight) == .regular)
    #expect(Font.Weight(strokeWeight: IconWeight.range.lowerBound) == .thin && Font.Weight(strokeWeight: IconWeight.range.upperBound) == .heavy)
    #expect(NSFont.Weight(strokeWeight: IconWeight.defaultWeight) == .regular)
}
