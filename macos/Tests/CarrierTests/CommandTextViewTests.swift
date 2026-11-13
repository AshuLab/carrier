import AppKit
import CarrierCore
import Observation
import SwiftUI
import XCTest
@testable import Carrier

@Observable @MainActor fileprivate final class Probe {
    var text = ""
    var cursor = 0
    var tentative: Range<Int>?
    var dictated: String?
}

fileprivate struct ProbeBox: View {
    @Bindable var probe: Probe
    var body: some View {
        CommandTextView(text: $probe.text, cursor: $probe.cursor, tentative: probe.tentative, dictated: probe.dictated, focus: .constant(false), placeholder: "", minLines: 3, commands: [], onKey: { _ in false })
            .frame(width: 600)
    }
}


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

    /// A dictation writes where the caret was and not at the end, the partial text has the provisional colour and a dotted underline and
    /// turns normal when it is final.
    func testADictationWritesInPlaceInTheProvisionalColourAndTurnsNormalWhenFinal() throws {
        let probe = Probe()
        probe.text = "uno dos"
        probe.cursor = 4
        let host = NSHostingView(rootView: ProbeBox(probe: probe))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(textView(in: host))
        func colour(at index: Int) -> NSColor? { view.textStorage?.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor }
        func underline(at index: Int) -> Int? { view.textStorage?.attribute(.underlineStyle, at: index, effectiveRange: nil) as? Int }

        var tentative = TentativeText(caret: 4, in: probe.text)
        for (event, secondary) in [(DictationEvent.partial("hola mun"), true), (.final("hola mundo "), false)] {
            let edit = try XCTUnwrap(tentative.apply(event, to: probe.text, caret: probe.cursor))
            (probe.text, probe.cursor, probe.tentative, probe.dictated) = (edit.text, edit.caret, tentative.range, edit.text)
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.string, edit.text)
            XCTAssertEqual(view.selectedRange().location, edit.caret)
            XCTAssertEqual(colour(at: 0), .labelColor)
            XCTAssertEqual(colour(at: 4), secondary ? PillTextView.tentativeColor : .labelColor)
            XCTAssertEqual(colour(at: view.string.utf16.count - 1), .labelColor)
            // the cue that is not a colour: the partial text only is underlined
            XCTAssertNil(underline(at: 0))
            XCTAssertEqual(underline(at: 4) != nil, secondary)
            XCTAssertNil(underline(at: view.string.utf16.count - 1))
        }
        XCTAssertEqual(view.string, "uno hola mundo dos")
        XCTAssertEqual(view.selectedRange().location, 15)
    }

    private func host(_ probe: Probe) -> (NSHostingView<ProbeBox>, PillTextView) {
        let host = NSHostingView(rootView: ProbeBox(probe: probe))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        return (host, textView(in: host)!)
    }

    /// A dictation whose first and only write is a final (a model that answers at the end) leaves the caret after the text it wrote, in the
    /// middle of the text, and not at the end of the whole text; a text that comes from outside still puts it at the end.
    func testAFinalWrittenInTheMiddleLeavesTheCaretAfterItAndAnOutsideTextLeavesItAtTheEnd() throws {
        let probe = Probe()
        probe.text = "uno dos"
        probe.cursor = 4
        let (host, view) = host(probe)
        var tentative = TentativeText(caret: 4, in: probe.text)
        let edit = try XCTUnwrap(tentative.apply(.final("hola mundo "), to: probe.text, caret: 4))
        (probe.text, probe.cursor, probe.dictated) = (edit.text, edit.caret, edit.text)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.string, "uno hola mundo dos")
        XCTAssertEqual(view.selectedRange().location, 15)

        probe.text = "a message that came back"
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.selectedRange().location, ("a message that came back" as NSString).length)
    }

    /// With no list of commands to take, Tab leaves the text for the next control and types no tab; the list still takes it when it is open.
    func testTabWithNoListOfCommandsTypesNothingAndTheListTakesIt() throws {
        let probe = Probe()
        probe.text = "uno"
        let (_, view) = host(probe)
        view.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(view.string, "uno")

        var keys: [CommandTextView.Key] = []
        let taken = CommandTextView(
            text: .constant("uno"), cursor: .constant(0), focus: .constant(false), placeholder: "", minLines: 3, commands: [],
            onKey: { keys.append($0); return true }
        )
        let coordinator = taken.makeCoordinator()
        XCTAssertTrue(coordinator.textView(view, doCommandBy: #selector(NSResponder.insertTab(_:))))
        XCTAssertEqual(keys, [.tab])
        XCTAssertEqual(view.string, "uno")
    }
}
