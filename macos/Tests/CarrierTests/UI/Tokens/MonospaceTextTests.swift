import AppKit
import SwiftUI
import Testing
@testable import CarrierCore
@testable import Carrier

/// The tests that write the monospace settings into the standard defaults, one at a time.
@Suite(.serialized) struct MonospaceInTheDefaults {
    private static let keys = [
        AppPreferences.monospaceFamilyKey, AppPreferences.monospaceSizeKey, AppPreferences.monospaceLineHeightKey,
        AppPreferences.monospaceLigaturesKey, AppPreferences.monospaceWrapKey, AppPreferences.monospaceLineNumbersKey,
        TypeScale.percentKey,
    ]

    private func withSettings<T>(_ settings: MonospaceSettings, _ body: () throws -> T) rethrows -> T {
        AppPreferences().monospace = settings
        defer { for key in Self.keys { UserDefaults.standard.removeObject(forKey: key) } }
        return try body()
    }

    @MainActor private func codeBlockHeight() throws -> Int {
        let block = CodeBlockView(language: "swift", code: "let a = 1\nlet b = 2")
        let renderer = ImageRenderer(content: block.frame(width: 400))
        renderer.scale = 2
        return try #require(renderer.cgImage).height
    }

    // A transcript block (a code block of a message, an approval) takes the family and the size the person chose.
    @MainActor @Test func aTranscriptBlockTakesTheFamilyAndTheSize() throws {
        try #require(MonospaceStyle.installedFamilies.contains("Menlo"))
        let font = withSettings(MonospaceSettings(family: "Menlo", size: 16)) { NSFont.code(12) }
        #expect(font.familyName == "Menlo")
        #expect(font.pointSize == 16)
        // the text size still multiplies it
        UserDefaults.standard.set(125, forKey: TypeScale.percentKey)
        #expect(withSettings(MonospaceSettings(size: 16)) { NSFont.code(12) }.pointSize == 20)
        // and the block that draws the code gets taller with the size
        let small = try withSettings(MonospaceSettings(size: 10), codeBlockHeight)
        let large = try withSettings(MonospaceSettings(size: 18), codeBlockHeight)
        #expect(large > small)
    }

    @MainActor @Test func aMissingFamilyDrawsInTheSystemsMonospacedFont() {
        let font = withSettings(MonospaceSettings(family: "No Such Mono")) { NSFont.code(12) }
        #expect(font.isFixedPitch)
        #expect(font.pointSize == 12)
    }
}
