import AppKit
import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

/// The ring for the fixture's numbers (1 merged, 1 in progress, 2 waiting) in a 128 pt square, read back pixel by pixel.
@MainActor private func rendered(scheme: ColorScheme = .light) throws -> NSBitmapImageRep {
    let view = SlicesRing(counts: [1, 1, 2], centre: "1/4", caption: "merged").environment(\.colorScheme, scheme)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
}

/// The colour on the ring's centre line, `turns` clockwise from 12 o'clock.
@MainActor private func pixel(_ image: NSBitmapImageRep, atTurn turns: Double) throws -> NSColor {
    let radius = (SlicesRing.size - SlicesRing.lineWidth) / 2
    let angle = turns * 2 * Double.pi
    let centre = Double(image.pixelsWide) / 2
    let x = centre + sin(angle) * radius * 2, y = centre - cos(angle) * radius * 2
    return try #require(image.colorAt(x: Int(x), y: Int(y))?.usingColorSpace(.sRGB))
}

@MainActor @Test(arguments: [ColorScheme.light, .dark])
func theRingPaintsMergedGreenThenInProgressBlueAndLeavesWaitingOnTheTrack(scheme: ColorScheme) throws {
    let image = try rendered(scheme: scheme)
    let merged = try pixel(image, atTurn: 0.125)
    #expect(merged.greenComponent > merged.blueComponent + 0.2 && merged.greenComponent > merged.redComponent + 0.2)
    let progress = try pixel(image, atTurn: 0.375)
    #expect(progress.blueComponent > progress.greenComponent + 0.2 && progress.blueComponent > progress.redComponent + 0.2)
    for turn in [0.625, 0.875] {
        let track = try pixel(image, atTurn: turn)
        #expect(abs(track.redComponent - track.blueComponent) < 0.1 && abs(track.redComponent - track.greenComponent) < 0.1)
    }
}

@MainActor @Test func theGapBetweenMergedAndInProgressIsTrackColoured() throws {
    let image = try rendered()
    // 12 o'clock is the gap before merged, 0.25 the one between merged and in progress
    for turn in [0.0, 0.25] {
        let gap = try pixel(image, atTurn: turn)
        #expect(abs(gap.redComponent - gap.blueComponent) < 0.1 && abs(gap.redComponent - gap.greenComponent) < 0.1)
    }
}

@MainActor @Test func aCompleteEpicIsOneUnbrokenGreenCircle() throws {
    let renderer = ImageRenderer(content: SlicesRing(counts: [4, 0, 0], centre: "4/4", caption: "all merged"))
    renderer.scale = 2
    let image = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    for turn in [0.0, 0.25, 0.5, 0.75] {
        let colour = try pixel(image, atTurn: turn)
        #expect(colour.greenComponent > colour.blueComponent + 0.2)
    }
}
