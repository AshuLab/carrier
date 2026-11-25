import AppKit
import CarrierCore
import CarrierUI
import SwiftUI

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
            let symbol = MainActor.assumeIsolated { IconImages.image(command.kind.symbol, bold: true).tinted(tint) }
            let fit = NSSize(width: 12, height: 12)
            symbol.draw(in: NSRect(x: padding + (icon - fit.width) / 2, y: (height - fit.height) / 2, width: fit.width, height: fit.height))
            name.draw(at: NSPoint(x: padding + icon + gap, y: (height - nameSize.height) / 2))
            return true
        }
        image.accessibilityDescription = "\(command.kind.title()) \(command.name)"
        return image
    }
}

/// A sent message: its text, with each command it names as the pill it was in the box.
func messageText(_ text: String, commands: [ChatCommand]) -> Text {
    // read before the pills are made, so the text is drawn again when the set or the weight of the icons changes
    _ = (IconAppearance.shared.set, IconAppearance.shared.weight)
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
