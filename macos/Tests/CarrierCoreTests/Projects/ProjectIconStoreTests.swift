import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CarrierCore

private func temporaryFolder() throws -> String {
    let folder = NSTemporaryDirectory() + "carrier-icon-store-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    return folder
}

private func writeTestImage(to url: URL, width: Int, height: Int, type: UTType = .png) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let cgImage = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, cgImage, nil)
    #expect(CGImageDestinationFinalize(destination))
}

private func imageInfo(at url: URL) throws -> (width: Int, height: Int, type: String?) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    let width = try #require(props[kCGImagePropertyPixelWidth] as? Int)
    let height = try #require(props[kCGImagePropertyPixelHeight] as? Int)
    return (width, height, CGImageSourceGetType(source) as String?)
}

@Test func savingCopiesReducesToAtMost256AsPNGAndSurvivesDeletingTheOriginal() throws {
    let carrier = try temporaryFolder()
    let sourceDir = try temporaryFolder()
    defer {
        try? FileManager.default.removeItem(atPath: carrier)
        try? FileManager.default.removeItem(atPath: sourceDir)
    }
    let store = ProjectIconStore(folder: carrier)

    // large JPEG is reduced to at most 256 px and saved as PNG under a random name
    let original = URL(fileURLWithPath: sourceDir + "/photo.jpg")
    try writeTestImage(to: original, width: 1024, height: 512, type: .jpeg)
    let copiedName = try store.save(from: original)
    #expect(copiedName.hasSuffix(".png"))
    #expect(copiedName != "photo.jpg")

    let copiedURL = try #require(store.existingURL(for: copiedName))
    #expect(copiedURL.deletingLastPathComponent().standardizedFileURL == URL(fileURLWithPath: CarrierPlaces(folder: carrier).projectIcons).standardizedFileURL)
    let info = try imageInfo(at: copiedURL)
    #expect(info.width == 256 && info.height == 128)
    #expect(info.type == UTType.png.identifier)

    // moving or deleting the original changes nothing
    let moved = URL(fileURLWithPath: sourceDir + "/moved.jpg")
    try FileManager.default.moveItem(at: original, to: moved)
    try FileManager.default.removeItem(at: moved)
    #expect(store.existingURL(for: copiedName) == copiedURL)
    #expect(try imageInfo(at: copiedURL).width == 256)

    // small image is not upscaled
    let small = URL(fileURLWithPath: sourceDir + "/small.png")
    try writeTestImage(to: small, width: 64, height: 48, type: .png)
    let smallName = try store.save(from: small)
    let smallInfo = try imageInfo(at: try #require(store.existingURL(for: smallName)))
    #expect(smallInfo.width == 64 && smallInfo.height == 48)
}

@Test func replacingAndDeletingManageCopiesAndMissingOrUnsafeNamesReturnNil() throws {
    let carrier = try temporaryFolder()
    let sourceDir = try temporaryFolder()
    defer {
        try? FileManager.default.removeItem(atPath: carrier)
        try? FileManager.default.removeItem(atPath: sourceDir)
    }
    let store = ProjectIconStore(folder: carrier)

    let firstSource = URL(fileURLWithPath: sourceDir + "/one.png")
    let secondSource = URL(fileURLWithPath: sourceDir + "/two.png")
    try writeTestImage(to: firstSource, width: 512, height: 512)
    try writeTestImage(to: secondSource, width: 300, height: 600)

    let first = try store.save(from: firstSource)
    #expect(store.existingURL(for: first) != nil)

    // replace deletes the previous copy and creates a new random file
    let second = try store.save(from: secondSource, replacing: first)
    #expect(second != first)
    #expect(store.existingURL(for: first) == nil)
    let secondURL = try #require(store.existingURL(for: second))
    let info = try imageInfo(at: secondURL)
    #expect(info.width == 128 && info.height == 256)

    // delete removes the file and ignores missing names
    store.delete(second)
    #expect(store.existingURL(for: second) == nil)
    store.delete("does-not-exist.png")
    store.delete(nil)

    // missing, empty and traversal names return nil and never escape the folder
    let sentinel = URL(fileURLWithPath: carrier + "/projects.json")
    try Data("{}".utf8).write(to: sentinel)
    for bad in ["missing.png", "", ".", "..", "../projects.json", "sub/icon.png", "/tmp/evil.png"] {
        #expect(store.existingURL(for: bad) == nil, Comment(rawValue: bad))
        store.delete(bad)
    }
    #expect(FileManager.default.fileExists(atPath: sentinel.path))

    // unreadable file throws without creating a file
    let textFile = URL(fileURLWithPath: sourceDir + "/notes.txt")
    try Data("not an image".utf8).write(to: textFile)
    #expect(throws: ProjectIconStoreError.unreadableImage) { try store.save(from: textFile) }
    #expect((try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) == [])
}
