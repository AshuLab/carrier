import Foundation

// The icon sets the person can choose in Appearance (docs/macos-ui.md, Icons). SF Symbols are the system's own; Tabler Icons and Lucide are bundled as SVGs
// (`Resources/TablerIcons`, `Resources/LucideIcons`, each with its licence) and drawn as template images, with the stroke rewritten to the weight chosen.

public enum IconSet: String, CaseIterable, Sendable {
    case tabler, lucide, sfSymbols

    public static let key = "appearance.iconSet"
    public static let defaultSet = IconSet.tabler

    public var title: String {
        switch self {
        case .tabler: "Tabler"
        case .lucide: "Lucide"
        case .sfSymbols: "SF Symbols"
        }
    }

    /// The saved set; the default while none was saved or the saved one is not one of these.
    public static func stored(in defaults: UserDefaults = .standard) -> IconSet {
        defaults.string(forKey: key).flatMap(IconSet.init(rawValue:)) ?? defaultSet
    }
}

/// Where an icon is in a set: an SVG of the bundle (`fill` draws an outline filled, for a set with no filled version of a solid icon) or an SF Symbol.
public enum IconAsset: Equatable, Sendable {
    case svg(folder: String, name: String, fill: Bool)
    case symbol(String)

    /// The SVG inside the bundle; nil for a symbol or a file the bundle lacks.
    public var url: URL? {
        guard case .svg(let folder, let name, _) = self else { return nil }
        return carrierResources.url(forResource: name, withExtension: "svg", subdirectory: folder)
    }
}

public func iconAsset(_ icon: AppIcon, in set: IconSet) -> IconAsset {
    let names = iconNames(icon)
    switch set {
    case .sfSymbols:
        return .symbol(names.symbol)
    case .tabler:
        // "outline/check" or "filled/circle-check": the folder of the set's own two kinds
        let parts = names.tabler.split(separator: "/").map(String.init)
        return .svg(folder: "TablerIcons/" + parts[0], name: parts[1], fill: false)
    case .lucide:
        let parts = names.lucide.split(separator: "+").map(String.init)
        return .svg(folder: "LucideIcons", name: parts[0], fill: parts.count > 1)
    }
}

/// An icon in each set, in the order the sets are listed: a Tabler path, a Lucide name (`+fill` draws it filled), an SF Symbol name. A switch, so a new
/// `AppIcon` does not build until it has all three.
private func iconNames(_ icon: AppIcon) -> (tabler: String, lucide: String, symbol: String) {
    switch icon {
    case .arrowDown: ("outline/arrow-down", "arrow-down", "arrow.down")
    case .arrowRight: ("outline/arrow-right", "arrow-right", "arrow.right")
    case .arrowUpRight: ("outline/arrow-up-right", "arrow-up-right", "arrow.up.right")
    case .ban: ("outline/ban", "ban", "slash.circle")
    case .bell: ("outline/bell", "bell", "bell")
    case .brain: ("outline/brain", "brain", "brain")
    case .brush: ("outline/brush", "paintbrush", "paintbrush")
    case .chartBar: ("outline/chart-bar", "chart-bar", "chart.bar")
    case .check: ("outline/check", "check", "checkmark")
    case .checkCircleFilled: ("filled/circle-check", "circle-check", "checkmark.circle.fill")
    case .chevronRight: ("outline/chevron-right", "chevron-right", "chevron.right")
    case .circle: ("outline/circle", "circle", "circle")
    case .close: ("outline/x", "x", "xmark")
    case .coin: ("outline/coin", "coins", "dollarsign.circle")
    case .copy: ("outline/copy", "copy", "doc.on.doc")
    case .cpu: ("outline/cpu", "cpu", "cpu")
    case .cube: ("outline/cube", "box", "cube")
    case .cup: ("outline/cup", "coffee", "cup.and.saucer")
    case .desktop: ("outline/device-desktop", "monitor", "desktopcomputer")
    case .dots: ("outline/dots", "ellipsis", "ellipsis")
    case .download: ("outline/circle-arrow-down", "circle-arrow-down", "arrow.down.circle")
    case .downloadTray: ("outline/download", "download", "arrow.down.to.line")
    case .exchange: ("outline/arrows-exchange", "arrow-left-right", "arrow.left.arrow.right")
    case .exclamation: ("outline/exclamation-mark", "exclamation-mark", "exclamationmark")
    case .externalLink: ("outline/external-link", "external-link", "arrow.up.right.square")
    case .eye: ("outline/eye", "eye", "eye")
    case .eyeOff: ("outline/eye-off", "eye-off", "eye.slash")
    case .fileText: ("outline/file-text", "file-text", "doc.text")
    case .folder: ("outline/folder", "folder", "folder")
    case .folderPlus: ("outline/folder-plus", "folder-plus", "folder.badge.plus")
    case .folderQuestion: ("outline/folder-question", "folder-search", "questionmark.folder")
    case .hash: ("outline/hash", "hash", "number")
    case .help: ("outline/help-circle", "circle-question-mark", "questionmark.circle")
    case .history: ("outline/history", "history", "clock.arrow.circlepath")
    case .inbox: ("outline/inbox", "inbox", "tray.full")
    case .info: ("outline/info-circle", "info", "info.circle")
    case .keyboard: ("outline/keyboard", "keyboard", "keyboard")
    case .lock: ("outline/lock", "lock", "lock")
    case .lockOpen: ("outline/lock-open", "lock-open", "lock.open")
    case .messages: ("outline/messages", "messages-square", "bubble.left.and.text.bubble.right")
    case .microphone: ("outline/microphone", "mic", "mic")
    case .minus: ("outline/minus", "minus", "minus")
    case .playFilled: ("filled/player-play", "play+fill", "play.fill")
    case .plus: ("outline/plus", "plus", "plus")
    case .power: ("outline/power", "power", "power")
    case .question: ("outline/question-mark", "question-mark", "questionmark")
    case .radioOn: ("outline/circle-dot", "circle-dot", "largecircle.fill.circle")
    case .record: ("outline/player-record", "disc", "record.circle")
    case .refresh: ("outline/refresh", "refresh-cw", "arrow.clockwise")
    case .rotate: ("outline/rotate", "rotate-ccw", "arrow.counterclockwise")
    case .search: ("outline/search", "search", "magnifyingglass")
    case .send: ("outline/send", "send", "paperplane")
    case .server: ("outline/server", "server", "server.rack")
    case .settings: ("outline/settings", "settings", "gearshape")
    case .sidebar: ("outline/layout-sidebar", "panel-left", "sidebar.left")
    case .sliders: ("outline/adjustments-horizontal", "sliders-horizontal", "slider.horizontal.3")
    case .star: ("outline/star", "star", "star")
    case .stethoscope: ("outline/stethoscope", "stethoscope", "stethoscope")
    case .stopFilled: ("filled/player-stop", "square+fill", "stop.fill")
    case .terminal: ("outline/terminal", "terminal", "terminal")
    case .trash: ("outline/trash", "trash-2", "trash")
    case .undo: ("outline/arrow-back-up", "undo-2", "arrow.uturn.backward")
    case .users: ("outline/users", "users", "person.2")
    case .warningFilled: ("filled/alert-triangle", "triangle-alert", "exclamationmark.triangle.fill")
    case .world: ("outline/world", "globe", "globe")
    }
}
