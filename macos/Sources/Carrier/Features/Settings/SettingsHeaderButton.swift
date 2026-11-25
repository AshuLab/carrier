import CarrierCore

/// An action pill of the toolbar: what a screen with several of them (Watching's list, a repo's screen) puts there.
struct SettingsHeaderButton: Equatable {
    let title: String
    let icon: AppIcon
    var enabled = true
    var spinning = false
    var help = ""
}
