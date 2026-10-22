import AppKit
import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private let longDirectory = "packages/some-very-long-package-name/src/deeply/nested/directory/with/many/levels/and/even/more/"

/// The height of the path drawn at `width`, and whether its rightmost pixels have ink (the file name reaches the edge).
@MainActor private func render(_ directory: String, _ name: String, width: CGFloat) throws -> (height: Int, inkAtTheEnd: Bool) {
    let renderer = ImageRenderer(content: PathText(directory: directory, name: name).frame(width: width).environment(\.colorScheme, .dark))
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    let bitmap = NSBitmapImageRep(cgImage: image)
    var ink = false
    for x in max(0, bitmap.pixelsWide - 40)..<bitmap.pixelsWide {
        for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { ink = true }
    }
    return (image.height, ink)
}

// One line however long the path is, and the file name sits at the end, whole: the directory is what gives way.
@MainActor @Test func aVeryLongPathStaysOnOneLineAndKeepsItsFileName() throws {
    let short = try render("src/", "a.ts", width: 260)
    let long = try render(longDirectory, "TokenRefreshScheduler.ts", width: 260)
    #expect(long.height == short.height)
    #expect(long.inkAtTheEnd)
    #expect(short.inkAtTheEnd == false)
}

// The bundled SVG is really drawn (the system decodes it), and the fallback symbol is too.
@MainActor @Test func theFileIconDrawsTheBundledSVGAndTheFallbackSymbol() throws {
    for path in ["src/app.ts", "archive.xyz"] {
        let renderer = ImageRenderer(content: FileIconView(icon: fileIcon(path)).frame(width: 18, height: 18))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var ink = false
        for x in 0..<bitmap.pixelsWide { for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { ink = true } }
        #expect(ink, "\(path)")
    }
}
