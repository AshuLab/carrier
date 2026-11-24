import AppKit
import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

/// Whether any pixel in the middle third of the image has colour.
@MainActor private func hasInkInTheCentre(_ state: EmptyState) -> Bool {
    let renderer = ImageRenderer(content: EmptyStateView(state: state).frame(width: 300, height: 300).environment(\.colorScheme, .dark))
    renderer.scale = 1
    guard let cgImage = renderer.cgImage else { return false }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    let (w, h) = (bitmap.pixelsWide, bitmap.pixelsHigh)
    for x in stride(from: w / 3, to: 2 * w / 3, by: 2) {
        for y in stride(from: h / 3, to: 2 * h / 3, by: 2) where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { return true }
    }
    return false
}

@Test @MainActor func everyEmptyStateDrawsSomethingInTheCentre() {
    for state in EmptyState.allCases { #expect(hasInkInTheCentre(state), "\(state.title)") }
}
