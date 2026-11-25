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
    /// The range of `text` (plain UTF-16 units) a dictation is still hearing: drawn in a colour with a touch of the accent and with a dotted
    /// underline, so it does not rest on colour alone.
    var tentative: Range<Int>?
    /// The text a dictation last wrote: when `text` is it, the change is the dictation's, written in place, and the caret is where the box says
    /// and not at the end.
    var dictated: String?
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
    /// The text size the box is drawn at, the environment's when a view builds it (the saved one otherwise), so a change of it reaches `updateNSView`.
    var textSize = TypeScale.stored().percent

    static var font: NSFont { NSFont.scaled(14) }
    static var lineHeight: CGFloat { TypeScale.stored().size(22) }
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
        view.insertionPointColor = NSColor(context.environment.pieceTheme.accent)
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
        view.insertionPointColor = NSColor(context.environment.pieceTheme.accent)
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
                let outside = view.plain != text && text != dictated
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
            case #selector(NSResponder.insertTab(_:)):
                // with no list of commands to take, Tab goes on to the next control (the microphone, then Send) and types nothing
                if parent.onKey(.tab) == false { textView.window?.selectNextKeyView(textView) }
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.selectPreviousKeyView(textView)
                return true
            case #selector(NSResponder.moveUp(_:)): return parent.onKey(.up)
            case #selector(NSResponder.moveDown(_:)): return parent.onKey(.down)
            case #selector(NSResponder.cancelOperation(_:)): return parent.onKey(.escape)
            // Home and End only scroll in a text view; in the message box they take the caret to the start and the end of the text
            case #selector(NSResponder.scrollToBeginningOfDocument(_:)):
                textView.moveToBeginningOfDocument(nil)
                return true
            case #selector(NSResponder.scrollToEndOfDocument(_:)):
                textView.moveToEndOfDocument(nil)
                return true
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
