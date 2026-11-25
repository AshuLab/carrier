import CarrierCore
import SwiftUI

private struct WindowSizeKey: EnvironmentKey { static let defaultValue = CGSize(width: 1100, height: 700) }

extension EnvironmentValues {
    /// The main window's size, set by the panel for the sheets over it.
    public var windowSize: CGSize {
        get { self[WindowSizeKey.self] }
        set { self[WindowSizeKey.self] = newValue }
    }
}

private struct SheetSized: ViewModifier {
    @Environment(\.windowSize) private var window
    let maxWidth: Double

    func body(content: Content) -> some View {
        let size = sheetSize(windowWidth: window.width, windowHeight: window.height, maxWidth: maxWidth)
        content.frame(width: size.width, height: size.height)
    }
}

extension View {
    /// A sheet of the window's own: three quarters of it, so it grows and shrinks with the window (`sheetSize`), its width capped at `maxWidth`.
    public func windowSheetSize(maxWidth: Double = .infinity) -> some View { modifier(SheetSized(maxWidth: maxWidth)) }
}
