import AppKit
import CarrierCore

extension StatusHeaderView {
    /// The menu's heading as the connection says it: its words, and a dot grey while Carrier is stopped, green while it runs and orange when it needs a look.
    func show(_ status: (title: String, detail: String?, tone: ConnectionState.MenuTone)) {
        let dot: NSColor =
            switch status.tone {
            case .stopped: .tertiaryLabelColor
            case .running: .systemGreen
            case .attention: .systemOrange
            }
        show(title: status.title, detail: status.detail, dot: dot)
    }
}
