import AppKit
@testable import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private let longDirectory = "packages/some-very-long-package-name/src/deeply/nested/directory/with/many/levels/and/even/more/"

/// The height of the row drawn at `width`.
@MainActor private func rowHeight(_ directory: String, _ name: String, alsoIn: [String] = [], width: CGFloat) throws -> Int {
    let row = FileRow(
        path: directory + name, directory: directory, name: name, category: .code, icon: fileIcon(directory + name),
        added: 120, removed: 14, alsoIn: alsoIn
    )
    let renderer = ImageRenderer(content: FileRowView(row: row).frame(width: width).environment(\.colorScheme, .dark))
    renderer.scale = 1
    return try #require(renderer.cgImage).height
}

// A row is the name over one line of directory however long the path is: the directory gives way, cut in the middle.
@MainActor @Test func aVeryLongPathKeepsTheRowTheSameHeight() throws {
    let short = try rowHeight("src/", "a.ts", width: 360)
    #expect(try rowHeight(longDirectory, "TokenRefreshScheduler.ts", width: 360) == short)
    #expect(try rowHeight(longDirectory, "TokenRefreshScheduler.ts", alsoIn: ["Slice #642"], width: 360) == short)
}

// The bundled SVG is really drawn (the system decodes it), and the fallback symbol is too.
@MainActor @Test func theFileIconDrawsTheBundledSVGAndTheFallbackSymbol() throws {
    for path in ["src/app.ts", "archive.xyz"] {
        let renderer = ImageRenderer(content: FileIconView(icon: fileIcon(path)).frame(width: 20, height: 20))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var ink = false
        for x in 0..<bitmap.pixelsWide { for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { ink = true } }
        #expect(ink, "\(path)")
    }
}
