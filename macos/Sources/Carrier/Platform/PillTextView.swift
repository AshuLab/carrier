import AppKit
import CarrierCore
import SwiftUI

/// The text view: it shows the placeholder, pastes and copies plain text, and counts positions the way the plain text does, where a pill
/// is the `/name` it stands for.
final class PillTextView: NSTextView {
    var placeholder = ""

    /// Whether the text holds a pill: with none, the text is the plain text and positions are the same, and nothing needs counting.
    private var hasPills: Bool { (string as NSString).range(of: "\u{FFFC}").location != NSNotFound }

    var plain: String { hasPills ? plainText(textStorage ?? NSTextStorage()) : string }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        var attributes = CommandTextView.attributes
        attributes[.foregroundColor] = NSColor.placeholderTextColor
        NSAttributedString(string: placeholder, attributes: attributes).draw(in: bounds)
    }

    /// A paste that is long goes to the box as a card; any other is typed in as plain text.
    var onLargePaste: ((String) -> Bool)?

    override func paste(_ sender: Any?) {
        if let pasted = NSPasteboard.general.string(forType: .string), pasted.utf16.count > pastedTextThreshold, onLargePaste?(pasted) == true { return }
        pasteAsPlainText(sender)
    }

    /// In an empty box the caret has the height of the font and sits at the top of a line that is taller (the box fixes the line height), so
    /// it rode above the placeholder and above the first letter typed; it goes down to where the text is drawn.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var rect = rect
        if string.isEmpty {
            let font = CommandTextView.font
            let height = ceil(font.ascender - font.descender)
            rect.origin.y += max(0, CommandTextView.lineHeight - height)
            rect.size.height = height
        }
        super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
    }

    /// Files dropped on the text are the box's to attach, not the text's to type in as links: it takes them to the box, and shows the box
    /// as the drop target while they are over it. Anything else dragged in is the text's own.
    var onFiles: (([URL]) -> Bool)?
    var onFileDrag: ((Bool) -> Void)?

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        guard onFiles != nil else { return [] }
        return info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard fileURLs(sender).isEmpty else { onFileDrag?(true); return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        fileURLs(sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onFileDrag?(false)
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        fileURLs(sender).isEmpty ? super.prepareForDragOperation(sender) : true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        guard urls.isEmpty == false else { return super.performDragOperation(sender) }
        onFileDrag?(false)
        return onFiles?(urls) ?? false
    }

    /// ⌘↓ is the menu's "Jump to the Latest Message" as well, and the menu would take it before the text sees it. In the box it first takes the
    /// caret to the end of the text, as any text field does; with the caret already there (or the box empty) it is the menu's again.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard takesCommandDown(event) else { return super.performKeyEquivalent(with: event) }
        moveToEndOfDocument(nil)
        return true
    }

    /// Whether `event` is ⌘↓ with the caret somewhere before the end of the text, here: the window's shortcut monitor leaves it to the box.
    func takesCommandDown(_ event: NSEvent) -> Bool {
        let range = selectedRange()
        let atEnd = range.length == 0 && range.location == (string as NSString).length
        let commandDown = event.keyCode == 125 && event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
        return commandDown && atEnd == false && window?.firstResponder === self
    }

    /// ⌘Return does not reach `insertNewline` on its own (the system reads it as a shortcut), so the box asks the coordinator itself.
    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        guard isReturn, event.modifierFlags.contains(.command), let coordinator = delegate as? CommandTextView.Coordinator else {
            return super.keyDown(with: event)
        }
        _ = coordinator.pressedReturn(in: self, modifiers: event.modifierFlags)
    }

    override func copy(_ sender: Any?) {
        guard selectedRange().length > 0, let storage = textStorage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plainText(storage.attributedSubstring(from: selectedRange())), forType: .string)
    }

    override func cut(_ sender: Any?) {
        copy(sender)
        deleteBackward(sender)
    }

    /// Puts `text` in place of all of it (the undo remembers it) and the caret at a position of the plain text.
    func replace(with text: NSAttributedString, plainCursor: Int) {
        let all = NSRange(location: 0, length: (string as NSString).length)
        if shouldChangeText(in: all, replacementString: text.string) {
            textStorage?.replaceCharacters(in: all, with: text)
            didChangeText()
        }
        typingAttributes = CommandTextView.attributes
        setSelectedRange(NSRange(location: location(ofPlainOffset: plainCursor), length: 0))
        scrollRangeToVisible(selectedRange())
    }

    /// The colour of text still being guessed: the normal one with a touch of the accent, so it keeps the contrast the secondary colour loses
    /// over the box's glass; the dotted underline of `drawTentative` says it too, for whoever does not tell the colours apart. Read when drawn,
    /// so it follows the appearance and the accent.
    static let tentativeColor = NSColor(name: nil) { appearance in
        var color = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance { color = NSColor.labelColor.blended(withFraction: 0.4, of: NSColor(Color.themeAccent)) ?? .labelColor }
        return color
    }

    /// Draws the text of `range` (plain offsets) in the provisional colour and a dotted underline, and the rest in the normal colour with none.
    func drawTentative(_ range: Range<Int>?) {
        guard let storage = textStorage else { return }
        let whole = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: whole)
        storage.removeAttribute(.underlineStyle, range: whole)
        guard let range else { return }
        let from = location(ofPlainOffset: range.lowerBound), to = location(ofPlainOffset: range.upperBound)
        let drawn = NSRange(location: from, length: max(0, to - from))
        storage.addAttribute(.foregroundColor, value: Self.tentativeColor, range: drawn)
        storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.patternDot.union(.single).rawValue, range: drawn)
    }

    /// The position in the plain text of a position in the text.
    func plainOffset(of location: Int) -> Int {
        guard let storage = textStorage else { return location }
        let end = min(location, storage.length)
        guard hasPills else { return end }
        return (plainText(storage.attributedSubstring(from: NSRange(location: 0, length: end))) as NSString).length
    }

    /// The position in the text of a position in the plain text; a pill is crossed whole.
    func location(ofPlainOffset offset: Int) -> Int {
        guard let storage = textStorage else { return offset }
        guard hasPills else { return min(offset, storage.length) }
        var location = 0
        var counted = 0
        while location < storage.length, counted < offset {
            if let pill = storage.attribute(.attachment, at: location, effectiveRange: nil) as? PillAttachment {
                counted += (pill.plainText as NSString).length
            } else {
                counted += 1
            }
            location += 1
        }
        return location
    }
}

/// What the text says, with each pill as the `/name` it stands for.
private func plainText(_ text: NSAttributedString) -> String {
    var out = ""
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, range, _ in
        if let pill = value as? PillAttachment {
            out += pill.plainText
        } else {
            out += (text.string as NSString).substring(with: range)
        }
    }
    return out
}
