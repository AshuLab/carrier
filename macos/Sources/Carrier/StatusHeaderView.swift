import AppKit
import CarrierCore

/// The first line of the menu: a dot coloured by the state, the title in bold and the detail quieter. A view of its own because
/// a menu item with no action is drawn grey. It takes no clicks.
final class StatusHeaderView: NSView {
    private let dot = DotView()
    private let label = NSTextField(labelWithString: "")

    private static let inset: CGFloat = 14

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        addSubview(dot)
        addSubview(label)
        autoresizingMask = .width
    }

    required init?(coder: NSCoder) { nil }

    func show(_ status: (title: String, detail: String?, tone: ConnectionState.MenuTone)) {
        let text = NSMutableAttributedString(string: status.title, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        if let detail = status.detail {
            text.append(NSAttributedString(string: "   " + detail, attributes: [
                .font: NSFont.menuFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        label.attributedStringValue = text
        dot.color = switch status.tone {
        case .stopped: .tertiaryLabelColor
        case .running: .systemGreen
        case .attention: .systemOrange
        }
        dot.needsDisplay = true
        let size = label.intrinsicContentSize
        label.frame = NSRect(x: Self.inset + 16, y: (frame.height - size.height) / 2, width: size.width, height: size.height)
        dot.frame = NSRect(x: Self.inset, y: (frame.height - 8) / 2, width: 8, height: 8)
        setFrameSize(NSSize(width: max(280, label.frame.maxX + Self.inset), height: frame.height))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class DotView: NSView {
    var color = NSColor.tertiaryLabelColor

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
