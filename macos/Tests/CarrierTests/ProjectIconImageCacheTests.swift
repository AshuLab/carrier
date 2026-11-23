import AppKit
import CarrierCore
import CoreGraphics
import Foundation
import Testing
@testable import Carrier

private func makeCGImage(width: Int = 64, height: Int = 64) throws -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(red: 0.9, green: 0.3, blue: 0.2, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

@MainActor @Test func iconImageCacheLoadsValidPNGAndReturnsNilWhenMissingOrCorrupt() throws {
    let folder = NSTemporaryDirectory() + "carrier-icon-cache-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: folder) }

    let store = ProjectIconStore(folder: folder)
    let saved = try store.save(cgImage: try makeCGImage())

    let loaded = try #require(ProjectIconImageCache.image(named: saved, in: store))
    #expect(loaded.size.width > 0 && loaded.size.height > 0)

    // deleting the copy immediately makes it nil so the tile falls back to color and mark
    store.delete(saved)
    #expect(ProjectIconImageCache.image(named: saved, in: store) == nil)
    #expect(ProjectIconImageCache.image(named: "missing.png", in: store) == nil)

    // a corrupt file in project-icons does not fail and returns nil
    try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
    let corruptURL = try #require(store.fileURL(for: "broken.png"))
    try Data("not a png".utf8).write(to: corruptURL)
    #expect(ProjectIconImageCache.image(named: "broken.png", in: store) == nil)
}
