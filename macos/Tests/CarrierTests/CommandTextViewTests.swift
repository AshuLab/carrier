import AppKit
import CarrierCore
import SwiftUI
import XCTest
@testable import Carrier

@MainActor
final class CommandTextViewTests: XCTestCase {
    private func textView(in host: NSView) -> PillTextView? {
        if let view = host as? PillTextView { return view }
        for sub in host.subviews { if let found = textView(in: sub) { return found } }
        return nil
    }

    /// The text uses the whole width of the box, so wrapping and the selection reach its edge.
    func testTextUsesTheWholeWidthOfTheBox() throws {
        let box = CommandTextView(
            text: .constant("one two three four five six seven eight nine ten"), cursor: .constant(0), focus: .constant(false),
            placeholder: "", minLines: 3, commands: [], onKey: { _ in false }
        )
        let host = NSHostingView(rootView: box.frame(width: 600).fixedSize(horizontal: false, vertical: true))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(textView(in: host))
        XCTAssertEqual(view.frame.width, 600, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(view.textContainer).size.width, 600, accuracy: 1)

        // SwiftUI measures with trial widths (sizeThatFits sets one on the container): the next layout puts the real one back
        view.textContainer?.containerSize = NSSize(width: 290, height: CGFloat.greatestFiniteMagnitude)
        let scroll = try XCTUnwrap(view.enclosingScrollView)
        scroll.needsLayout = true
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(try XCTUnwrap(view.textContainer).size.width, 600, accuracy: 1)
    }

    /// Measuring at a trial width does not change how the box wraps: the same text is taller when narrower, and measured twice is the same.
    func testHeightIsMeasuredOnACopy() {
        let text = NSAttributedString(string: String(repeating: "word ", count: 40), attributes: CommandTextView.attributes)
        let wide = CommandTextView.height(of: text, width: 600)
        let narrow = CommandTextView.height(of: text, width: 150)
        XCTAssertGreaterThan(narrow, wide)
        XCTAssertEqual(CommandTextView.height(of: text, width: 600), wide)
    }
}
