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
    /// Set to true to put the caret in the text; the text resets it once it has.
    @Binding var focus: Bool
    var placeholder: String
    var minLines: Int
    var maxLines = 10
    var commands: [ChatCommand]
    /// What a key does for the box; true when the box took it.
    var onKey: (Key) -> Bool

    static let font = NSFont.systemFont(ofSize: 14)
    static let lineHeight: CGFloat = 22
    static let attributes: [NSAttributedString.Key: Any] = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        return [.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: style]
    }()

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
        view.autoresizingMask = NSView.AutoresizingMask.width
        view.typingAttributes = Self.attributes
        view.insertionPointColor = NSColor.controlAccentColor
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
        if view.hasMarkedText() == false {
            let rendered = render(text, commands: commands)
            if view.plain != text || view.string != rendered.string {
                view.replace(with: rendered, plainCursor: min(cursor, (text as NSString).length))
            } else if view.plainOffset(of: view.selectedRange().location) != cursor {
                view.setSelectedRange(NSRange(location: view.location(ofPlainOffset: cursor), length: 0))
            }
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
        guard let view = scroll.documentView as? PillTextView, let container = view.textContainer, let layout = view.layoutManager else { return nil }
        let width = proposal.width ?? 400
        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container).height
        let lines = CGFloat(minLines)...CGFloat(maxLines)
        return CGSize(width: width, height: min(max(used, lines.lowerBound * Self.lineHeight), lines.upperBound * Self.lineHeight))
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

        init(_ parent: CommandTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard updating == false, let view = notification.object as? PillTextView, view.hasMarkedText() == false else { return }
            let text = view.plain
            let cursor = view.plainOffset(of: view.selectedRange().location)
            let rendered = parent.render(text, commands: parent.commands)
            if view.string != rendered.string {
                updating = true
                view.replace(with: rendered, plainCursor: cursor)
                updating = false
            }
            view.typingAttributes = CommandTextView.attributes
            parent.text = text
            parent.cursor = cursor
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard updating == false, let view = notification.object as? PillTextView else { return }
            let cursor = view.plainOffset(of: view.selectedRange().location)
            if parent.cursor != cursor { parent.cursor = cursor }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)):
                // Enter sends, Shift+Enter adds a line
                if selector == #selector(NSResponder.insertLineBreak(_:)) || NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                return parent.onKey(.send)
            case #selector(NSResponder.insertTab(_:)): return parent.onKey(.tab)
            case #selector(NSResponder.moveUp(_:)): return parent.onKey(.up)
            case #selector(NSResponder.moveDown(_:)): return parent.onKey(.down)
            case #selector(NSResponder.cancelOperation(_:)): return parent.onKey(.escape)
            default: return false
            }
        }
    }
}

/// The scroll view: a click under the text puts the caret at its end.
private final class PillScrollView: NSScrollView {
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

    var plain: String { plainText(textStorage ?? NSTextStorage()) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        var attributes = CommandTextView.attributes
        attributes[.foregroundColor] = NSColor.placeholderTextColor
        NSAttributedString(string: placeholder, attributes: attributes).draw(in: bounds)
    }

    override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

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
    }

    /// The position in the plain text of a position in the text.
    func plainOffset(of location: Int) -> Int {
        guard let storage = textStorage else { return location }
        let end = min(location, storage.length)
        return (plainText(storage.attributedSubstring(from: NSRange(location: 0, length: end))) as NSString).length
    }

    /// The position in the text of a position in the plain text; a pill is crossed whole.
    func location(ofPlainOffset offset: Int) -> Int {
        guard let storage = textStorage else { return offset }
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
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
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
