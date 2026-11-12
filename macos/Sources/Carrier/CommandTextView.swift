import AppKit
import CarrierCore
import SwiftUI

/// The text of the message box. The text the app holds is plain (`/name` is what a command is in it); here a command the provider lists,
/// written whole and followed by a space, is a pill with its icon and the colour of its kind, that the caret crosses and Delete removes
/// as one. A `/` starts a command anywhere in the text, and `cursor` says where the caret is so the box can list what it leads to.
struct CommandTextView: NSViewRepresentable {
    enum Key { case send, tab, up, down, escape }

    @Binding var text: String
    /// Where the caret is, in UTF-16 units of `text`.
    @Binding var cursor: Int
    /// The range of `text` (plain UTF-16 units) a dictation is still hearing: drawn secondary, and the caret is where the box says, not at the end.
    var tentative: Range<Int>?
    /// Set to true to put the caret in the text; the text resets it once it has.
    @Binding var focus: Bool
    var placeholder: String
    var minLines: Int
    var maxLines = 10
    var commands: [ChatCommand]
    /// What a key does for the box; true when the box took it.
    var onKey: (Key) -> Bool
    /// The person changed the text (a key, a paste, a deletion): not a write of the box itself.
    var onTyped: () -> Void = {}
    /// Files dropped on the text: the box attaches them (true when it did).
    var onFiles: (([URL]) -> Bool)?
    var onFileDrag: ((Bool) -> Void)?
    /// A text pasted that is longer than `pastedTextThreshold`: the box keeps it beside the text (true when it did).
    var onLargePaste: ((String) -> Bool)?
    var sendKey = AppPreferences.defaultSendKey
    var writingTools = AppPreferences.defaultWritingTools
    var checksSpelling = AppPreferences.defaultChecksSpelling
    var correctsSpelling = AppPreferences.defaultCorrectsSpelling
    /// The text size the box is drawn at: read when the box is built, so a change of it reaches `updateNSView`.
    var textSize = TextSize.shared.percent

    static var font: NSFont { NSFont.scaled(14) }
    static var lineHeight: CGFloat { TextSize.shared.scale.size(22) }
    static var attributes: [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)

        let view = PillTextView(frame: .zero, textContainer: container)
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = true
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.textContainerInset = NSSize.zero
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        // a text view made in code starts with no room to grow: without these it stops at the height the box has and the lines after it are not reachable
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = NSView.AutoresizingMask.width
        view.typingAttributes = Self.attributes
        view.insertionPointColor = NSColor(Color.themeAccent)
        view.setAccessibilityLabel(placeholder)

        let scroll = PillScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let view = scroll.documentView as? PillTextView else { return }
        coordinator.updating = true
        defer { coordinator.updating = false }
        view.placeholder = placeholder
        view.onFiles = onFiles
        view.onFileDrag = onFileDrag
        view.onLargePaste = onLargePaste
        view.insertionPointColor = NSColor(Color.themeAccent)
        // Writing Tools (Apple Intelligence) offer to rewrite what is selected, over the text: they are the person's to switch on
        view.writingToolsBehavior = writingTools ? .default : .none
        view.isContinuousSpellCheckingEnabled = checksSpelling
        view.isAutomaticSpellingCorrectionEnabled = correctsSpelling
        let rescaled = coordinator.textSize != textSize
        coordinator.textSize = textSize
        // what the box itself reported is already in the text view: only a text or a command list that came from outside needs the work
        let settled = rescaled == false && text == coordinator.reported && commands == coordinator.reportedCommands && tentative == coordinator.reportedTentative
        if view.hasMarkedText() == false, settled == false {
            let rendered = render(text, commands: commands)
            let length = (text as NSString).length
            if rescaled || view.plain != text || view.string != rendered.string {
                // a text put in from outside (a refused message that came back, a queued one taken back to edit) is written for the person
                // to go on at its end; the caret the box knew was the one of the text it replaced
                // a dictation writes in place: the caret is the one the box set
                let dictating = tentative != nil || coordinator.reportedTentative != nil
                let outside = view.plain != text && dictating == false
                view.replace(with: rendered, plainCursor: outside ? length : min(cursor, length))
                if outside { DispatchQueue.main.async { if cursor != length { cursor = length } } }
            } else if view.plainOffset(of: view.selectedRange().location) != cursor {
                view.setSelectedRange(NSRange(location: view.location(ofPlainOffset: cursor), length: 0))
            }
            view.drawTentative(tentative)
            coordinator.reported = text
            coordinator.reportedCommands = commands
            coordinator.reportedTentative = tentative
        }
        if focus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let window = view.window else { return }
                window.makeFirstResponder(view)
                focus = false
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scroll: NSScrollView, context: Context) -> CGSize? {
        guard let view = scroll.documentView as? PillTextView else { return nil }
        let width = proposal.width ?? 400
        // SwiftUI asks several times for each key with the same text and width: the layout is made once
        let coordinator = context.coordinator
        var key = Hasher()
        key.combine(view.string)
        key.combine(width)
        key.combine(textSize)
        let used: CGFloat
        if let known = coordinator.measured, known.key == key.finalize() {
            used = known.height
        } else {
            used = Self.height(of: view.attributedString(), width: width)
            var again = Hasher()
            again.combine(view.string)
            again.combine(width)
            again.combine(textSize)
            coordinator.measured = (again.finalize(), used)
        }
        let lines = CGFloat(minLines)...CGFloat(maxLines)
        return CGSize(width: width, height: min(max(used, lines.lowerBound * Self.lineHeight), lines.upperBound * Self.lineHeight))
    }

    /// How tall `text` is at `width`, measured on a copy: SwiftUI asks with trial widths, and the box's own container keeps the real one.
    static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        return layout.usedRect(for: container).height
    }

    /// The text with each command written whole and followed by a space as a pill.
    func render(_ text: String, commands: [ChatCommand]) -> NSAttributedString {
        let ns = text as NSString
        let out = NSMutableAttributedString()
        var plainFrom = 0
        for span in commandSpans(in: text, among: commands) {
            out.append(NSAttributedString(string: ns.substring(with: NSRange(location: plainFrom, length: span.range.location - plainFrom))))
            out.append(NSAttributedString(attachment: PillAttachment(span.command)))
            plainFrom = NSMaxRange(span.range)
        }
        out.append(NSAttributedString(string: ns.substring(from: plainFrom)))
        out.addAttributes(Self.attributes, range: NSRange(location: 0, length: out.length))
        return out
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommandTextView
        /// Set while the box is the one changing the text view, so what it reports back is not taken for the person's edit.
        var updating = false
        /// The text size the text view was last drawn at.
        var textSize: Int
        /// The text and the commands the box last put in the text view or took from it: what is already there.
        var reported = ""
        var reportedCommands: [ChatCommand] = []
        var reportedTentative: Range<Int>?
        /// The height the last layout measured, and what it was measured for.
        var measured: (key: Int, height: CGFloat)?

        init(_ parent: CommandTextView) {
            self.parent = parent
            textSize = parent.textSize
        }

        func textDidChange(_ notification: Notification) {
            guard updating == false, let view = notification.object as? PillTextView, view.hasMarkedText() == false else { return }
            let text = view.plain
            let cursor = view.plainOffset(of: view.selectedRange().location)
            // a command becomes a pill only where there is a slash: no other text needs rendering again
            if text.contains("/") {
                let rendered = parent.render(text, commands: parent.commands)
                if view.string != rendered.string {
                    updating = true
                    view.replace(with: rendered, plainCursor: cursor)
                    updating = false
                }
            }
            view.typingAttributes = CommandTextView.attributes
            view.scrollRangeToVisible(view.selectedRange())
            reported = text
            reportedCommands = parent.commands
            parent.text = text
            parent.cursor = cursor
            parent.onTyped()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard updating == false, let view = notification.object as? PillTextView else { return }
            let cursor = view.plainOffset(of: view.selectedRange().location)
            if parent.cursor != cursor { parent.cursor = cursor }
        }

        /// Return with these modifiers: the key chosen in Settings sends, any other makes a new line.
        func pressedReturn(in textView: NSTextView, modifiers: NSEvent.ModifierFlags) -> Bool {
            if parent.sendKey.sends(command: modifiers.contains(.command), shift: modifiers.contains(.shift)) { return parent.onKey(.send) }
            textView.insertNewlineIgnoringFieldEditor(nil)
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)): return pressedReturn(in: textView, modifiers: NSApp.currentEvent?.modifierFlags ?? [])
            case #selector(NSResponder.insertLineBreak(_:)):
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            case #selector(NSResponder.insertTab(_:)): return parent.onKey(.tab)
            case #selector(NSResponder.moveUp(_:)): return parent.onKey(.up)
            case #selector(NSResponder.moveDown(_:)): return parent.onKey(.down)
            case #selector(NSResponder.cancelOperation(_:)): return parent.onKey(.escape)
            default: return false
            }
        }
    }
}

/// The scroll view: the text is as wide as the view in every layout (`sizeThatFits` sets trial widths on the container while SwiftUI
/// measures, and nothing else puts the real one back), and a click under the text puts the caret at its end.
private final class PillScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let view = documentView as? NSTextView, let container = view.textContainer else { return }
        let width = contentSize.width
        if view.frame.width != width { view.setFrameSize(NSSize(width: width, height: view.frame.height)) }
        if container.size.width != width { container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude) }
        // as tall as the text, and at least as the box, so what does not fit scrolls inside it
        if let layout = view.layoutManager {
            layout.ensureLayout(for: container)
            let height = max(layout.usedRect(for: container).height, contentSize.height)
            if abs(view.frame.height - height) > 0.5 { view.setFrameSize(NSSize(width: width, height: height)) }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let view = documentView as? NSTextView else { return super.mouseDown(with: event) }
        window?.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
    }
}

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

    /// Draws the text of `range` (plain offsets) secondary and the rest in the normal colour.
    func drawTentative(_ range: Range<Int>?) {
        guard let storage = textStorage else { return }
        let whole = NSRange(location: 0, length: storage.length)
        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: whole)
        guard let range else { return }
        let from = location(ofPlainOffset: range.lowerBound), to = location(ofPlainOffset: range.upperBound)
        storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: NSRange(location: from, length: max(0, to - from)))
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

/// A command in the text: its icon over a tint of its kind, then its name.
final class PillAttachment: NSTextAttachment {
    let plainText: String

    init(_ command: ChatCommand) {
        plainText = "/\(command.name)"
        super.init(data: nil, ofType: nil)
        let image = Self.image(for: command)
        self.image = image
        bounds = CGRect(x: 0, y: -6, width: image.size.width, height: image.size.height)
    }

    required init?(coder: NSCoder) { fatalError("a pill is not stored") }

    static func image(for command: ChatCommand) -> NSImage {
        let font = NSFont.scaledMono(12, weight: .medium)
        let name = NSAttributedString(string: "/\(command.name)", attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        let nameSize = name.size()
        let padding: CGFloat = 7, icon: CGFloat = 12, gap: CGFloat = 5, height: CGFloat = 20
        let size = NSSize(width: ceil(padding + icon + gap + nameSize.width + padding), height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            let tint = command.kind.nsColor
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            tint.withAlphaComponent(0.2).setFill()
            shape.fill()
            tint.withAlphaComponent(0.5).setStroke()
            shape.stroke()
            let configuration = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold).applying(.init(paletteColors: [tint]))
            if let symbol = NSImage(systemSymbolName: command.kind.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                let fit = symbol.size
                symbol.draw(in: NSRect(x: padding + (icon - fit.width) / 2, y: (height - fit.height) / 2, width: fit.width, height: fit.height))
            }
            name.draw(at: NSPoint(x: padding + icon + gap, y: (height - nameSize.height) / 2))
            return true
        }
        image.accessibilityDescription = "\(command.kind.title) \(command.name)"
        return image
    }
}

/// A sent message: its text, with each command it names as the pill it was in the box.
func messageText(_ text: String, commands: [ChatCommand]) -> Text {
    let ns = text as NSString
    var result = Text("")
    var from = 0
    for span in commandSpans(in: text, among: commands, ended: true) {
        let before = ns.substring(with: NSRange(location: from, length: span.range.location - from))
        let pill = Text(Image(nsImage: PillAttachment.image(for: span.command))).baselineOffset(-5)
        result = Text("\(result)\(before)\(pill)")
        from = NSMaxRange(span.range)
    }
    return Text("\(result)\(ns.substring(from: from))")
}
