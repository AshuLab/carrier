import AppKit
import CarrierCore
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

@MainActor @Test func theImageForAppKitIsNeverEmptyWhateverTheSet() {
    for icon in AppIcon.allCases { #expect(IconImages.image(icon).size.width > 0, Comment(rawValue: "\(icon)")) }
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

@MainActor @Test func aLabelForTheSystemTakesTheSFSymbolOfTheIconAndAnInlineImageIsBuiltInEverySet() {
    _ = Label("Reveal", systemIcon: .folder)
    _ = Image(inline: .gitBranch)
    #expect(iconAsset(.folder, in: .sfSymbols) == .symbol("folder"))
}
