import AppKit
import CarrierCore
import SwiftUI

/// How each kind of command looks wherever it shows (the list, the pill in the text): its icon, its colour and its name, so a skill and
/// a command of the provider are told apart at a glance.
extension ChatCommand.Kind {
    func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        self == .skill ? Copy.chatSkill(bundle: bundle, locale: locale) : Copy.chatCommand(bundle: bundle, locale: locale)
    }
    func plural(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        self == .skill ? Copy.chatSkillPlural(bundle: bundle, locale: locale) : Copy.chatCommandPlural(bundle: bundle, locale: locale)
    }
    var symbol: AppIcon { self == .skill ? .sparkles : .command }
    var nsColor: NSColor { self == .skill ? .systemPurple : .systemTeal }
    var color: Color { Color(nsColor: nsColor) }
}
