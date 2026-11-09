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
        XCTAssertEqual(view.writingToolsBehavior, .none)
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

    /// A box with its own preferences on screen: the text view, and a count of the sends it reported.
    private func hosted(
        sendKey: SendKey = .return, writingTools: Bool = false, checksSpelling: Bool = true, correctsSpelling: Bool = false, sent: @escaping () -> Void = {}
    ) throws -> PillTextView {
        let box = CommandTextView(
            text: .constant(""), cursor: .constant(0), focus: .constant(false), placeholder: "", minLines: 3, commands: [],
            onKey: { key in
                if key == .send { sent() }
                return key == .send
            },
            sendKey: sendKey, writingTools: writingTools, checksSpelling: checksSpelling, correctsSpelling: correctsSpelling
        )
        let host = NSHostingView(rootView: box.frame(width: 600).fixedSize(horizontal: false, vertical: true))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return try XCTUnwrap(textView(in: host))
    }

    private func keyDown(_ view: PillTextView, command: Bool, shift: Bool = false) {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        )
        let coordinator = view.delegate as? CommandTextView.Coordinator
        _ = coordinator?.pressedReturn(in: view, modifiers: event?.modifierFlags ?? [])
    }

    /// The chosen key sends and the other makes a new line, in each of the two settings; Shift+Return is a new line in both.
    func testTheChosenKeySendsAndTheOtherMakesANewLine() throws {
        for (sendKey, sendsWithCommand) in [(SendKey.return, false), (.commandReturn, true)] {
            for command in [false, true] {
                var sent = 0
                let view = try hosted(sendKey: sendKey) { sent += 1 }
                keyDown(view, command: command)
                let sendsNow = command == sendsWithCommand
                XCTAssertEqual(sent, sendsNow ? 1 : 0, "\(sendKey) command \(command)")
                XCTAssertEqual(view.string, sendsNow ? "" : "\n", "\(sendKey) command \(command)")
            }
            var sent = 0
            let view = try hosted(sendKey: sendKey) { sent += 1 }
            keyDown(view, command: sendsWithCommand, shift: true)
            XCTAssertEqual(sent, 0)
            XCTAssertEqual(view.string, "\n")
        }
    }

    /// ⌘Return reaches the box through `keyDown`, which the system does not turn into a new line command by itself.
    func testCommandReturnIsReadByTheBoxItself() throws {
        var sent = 0
        let view = try hosted(sendKey: .commandReturn) { sent += 1 }
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0, windowNumber: 0, context: nil,
            characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36
        ))
        view.keyDown(with: event)
        XCTAssertEqual(sent, 1)
    }

    func testTheSystemsHelpFollowTheSettings() throws {
        let off = try hosted()
        XCTAssertEqual(off.writingToolsBehavior, .none)
        XCTAssertTrue(off.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(off.isAutomaticSpellingCorrectionEnabled)
        let on = try hosted(writingTools: true, checksSpelling: false, correctsSpelling: true)
        XCTAssertNotEqual(on.writingToolsBehavior, .none)
        XCTAssertFalse(on.isContinuousSpellCheckingEnabled)
        XCTAssertTrue(on.isAutomaticSpellingCorrectionEnabled)
    }

    /// ⌘L sets the box's focus flag: the caret goes to the text view.
    func testTheFocusFlagPutsTheCaretInTheBox() async throws {
        let box = CommandTextView(
            text: .constant(""), cursor: .constant(0), focus: .constant(true), placeholder: "", minLines: 3, commands: [], onKey: { _ in false }
        )
        let host = NSHostingView(rootView: box.frame(width: 600).fixedSize(horizontal: false, vertical: true))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(textView(in: host))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(window.firstResponder === view)
    }
}
