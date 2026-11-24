import SwiftUI
import Testing
@testable import Carrier

@MainActor private func height(_ code: String, width: CGFloat) throws -> Int {
    let renderer = ImageRenderer(content: CodeBlockView(language: "bash", code: code).frame(width: width))
    renderer.scale = 1
    return try #require(renderer.cgImage).height
}

// With Wrap long lines on (the default) a line longer than the card breaks and the block grows taller, instead of running off to the right.
@MainActor @Test func aLongLineOfACodeBlockWrapsInsteadOfRunningOffTheCard() throws {
    let short = try height("git status", width: 300)
    let long = try height("git diff CHANGELOG.md | grep \"^+\" | grep -v \"^+++\" | cut -c1-120; git add CHANGELOG.md macos/Sources/Carrier/SettingsTabs.swift", width: 300)
    #expect(long > short + 20)
}
