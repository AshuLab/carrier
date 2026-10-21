import AppKit
import SwiftUI
import Testing
@testable import Carrier

/// The row title drawn at `width` points (2x) with a very long name, as pixel bytes of its rightmost 30 points.
@MainActor private func rightEdge(issue: Int, width: CGFloat) throws -> [UInt8] {
    let name = String(repeating: "a-very-long-repository-name-", count: 6)
    let view = SidebarRowTitle(name: name, issue: issue).frame(width: width, height: 24, alignment: .leading)
        .environment(\.colorScheme, .light).background(Color.white)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    let strip = try #require(image.cropping(to: CGRect(x: image.width - 60, y: 0, width: 60, height: image.height)))
    let bitmap = NSBitmapImageRep(cgImage: strip)
    return Array(UnsafeBufferPointer(start: bitmap.bitmapData, count: bitmap.bytesPerRow * bitmap.pixelsHigh))
}

// Same layout, other digits: the right edge differs only if the number is drawn there, and the name cannot have pushed it out.
@MainActor @Test(arguments: [CGFloat(220), 320])
func theIssueNumberIsDrawnAtTheEdgeWhateverTheNameLength(width: CGFloat) throws {
    #expect(try rightEdge(issue: 1111, width: width) != rightEdge(issue: 8888, width: width))
}
