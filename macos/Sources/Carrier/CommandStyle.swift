import AppKit
import CarrierCore
import SwiftUI

/// How each kind of command looks wherever it shows (the list, the pill in the text): its icon, its colour and its name, so a skill and
/// a command of the provider are told apart at a glance.
extension ChatCommand.Kind {
    var title: String { self == .skill ? "Skill" : "Command" }
    var plural: String { self == .skill ? "Skills" : "Commands" }
    var symbol: String { self == .skill ? "sparkles" : "command" }
    var nsColor: NSColor { self == .skill ? .systemPurple : .systemTeal }
    var color: Color { Color(nsColor: nsColor) }
}
