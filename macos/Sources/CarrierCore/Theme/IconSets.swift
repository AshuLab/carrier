import Foundation

// The icon sets the person can choose in Appearance (docs/ui.md, Icons). SF Symbols are the system's own; Tabler Icons and Lucide are bundled as SVGs
// (`Resources/TablerIcons`, `Resources/LucideIcons`, each with its licence) and drawn as template images, with the stroke rewritten to the weight chosen.

public enum IconSet: String, CaseIterable, Sendable {
    case tabler, lucide, sfSymbols

    public static let defaultSet = Preference.appearanceIconSet.defaultValue

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .tabler: Copy.choiceIconSetTabler(bundle: bundle, locale: locale)
        case .lucide: Copy.choiceIconSetLucide(bundle: bundle, locale: locale)
        case .sfSymbols: Copy.choiceIconSetSfSymbols(bundle: bundle, locale: locale)
        }
    }

    /// The saved set; the default while none was saved or the saved one is not one of these.
    public static func stored(in defaults: UserDefaults = .standard) -> IconSet {
        AppPreferences(defaults: defaults).value(Preference.appearanceIconSet)
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

extension AppIcon {
    /// The SF Symbol of the icon, for what the system draws (a menu, the toolbar) whatever the set is.
    public var systemSymbolName: String { iconNames(self).symbol }
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
    case .activity: ("outline/activity", "activity", "waveform.path.ecg")
    case .alignLeft: ("outline/align-left", "align-left", "text.alignleft")
    case .archive: ("outline/archive", "archive", "archivebox")
    case .arrowDown: ("outline/arrow-down", "arrow-down", "arrow.down")
    case .arrowLeft: ("outline/arrow-left", "arrow-left", "arrow.left")
    case .arrowRight: ("outline/arrow-right", "arrow-right", "arrow.right")
    case .arrowUp: ("outline/arrow-up", "arrow-up", "arrow.up")
    case .arrowUpRight: ("outline/arrow-up-right", "arrow-up-right", "arrow.up.right")
    case .arrowsMaximize: ("outline/arrows-maximize", "maximize-2", "arrow.up.left.and.arrow.down.right")
    case .arrowsMinimize: ("outline/arrows-minimize", "minimize-2", "arrow.down.right.and.arrow.up.left")
    case .arrowsMove: ("outline/arrows-move", "move", "arrow.up.and.down.and.arrow.left.and.right")
    case .ban: ("outline/ban", "ban", "slash.circle")
    case .bell: ("outline/bell", "bell", "bell")
    case .bolt: ("outline/bolt", "zap", "bolt.horizontal.circle")
    case .book: ("outline/book", "book", "book.closed")
    case .braces: ("outline/braces", "braces", "curlybraces")
    case .brain: ("outline/brain", "brain", "brain")
    case .brush: ("outline/brush", "paintbrush", "paintbrush")
    case .calendar: ("outline/calendar", "calendar", "calendar")
    case .chartBar: ("outline/chart-bar", "chart-bar", "chart.bar")
    case .check: ("outline/check", "check", "checkmark")
    case .checkCircle: ("outline/circle-check", "circle-check", "checkmark.circle")
    case .checkCircleFilled: ("filled/circle-check", "circle-check", "checkmark.circle.fill")
    case .chevronDown: ("outline/chevron-down", "chevron-down", "chevron.down")
    case .chevronLeft: ("outline/chevron-left", "chevron-left", "chevron.left")
    case .chevronRight: ("outline/chevron-right", "chevron-right", "chevron.right")
    case .chevronUp: ("outline/chevron-up", "chevron-up", "chevron.up")
    case .circle: ("outline/circle", "circle", "circle")
    case .circleFilled: ("filled/circle", "circle+fill", "circle.fill")
    case .circlePlus: ("outline/circle-plus", "circle-plus", "plus.circle")
    case .clipboard: ("outline/clipboard", "clipboard", "clipboard")
    case .clock: ("outline/clock", "clock", "clock")
    case .close: ("outline/x", "x", "xmark")
    case .closeCircle: ("outline/circle-x", "circle-x", "xmark.circle")
    case .closeCircleFilled: ("filled/circle-x", "circle-x", "xmark.circle.fill")
    case .cloud: ("outline/cloud", "cloud", "icloud")
    case .cloudOff: ("outline/cloud-off", "cloud-off", "icloud.slash")
    case .cloudWarning: ("outline/cloud-exclamation", "cloud-alert", "exclamationmark.icloud")
    case .code: ("outline/code", "code-xml", "chevron.left.forwardslash.chevron.right")
    case .coin: ("outline/coin", "coins", "dollarsign.circle")
    case .columns3: ("outline/columns-3", "columns-3", "rectangle.split.3x1")
    case .command: ("outline/command", "command", "command")
    case .copy: ("outline/copy", "copy", "doc.on.doc")
    case .copyPlus: ("outline/copy-plus", "copy-plus", "plus.rectangle.on.rectangle")
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
    case .file: ("outline/file", "file", "doc")
    case .fileDescription: ("outline/file-description", "file-text", "doc.richtext")
    case .fileOff: ("outline/file-off", "file-x", "text.badge.xmark")
    case .fileText: ("outline/file-text", "file-text", "doc.text")
    case .filter: ("outline/filter", "list-filter", "line.3.horizontal.decrease")
    case .flag: ("outline/flag", "flag", "flag")
    case .folder: ("outline/folder", "folder", "folder")
    case .folderCog: ("outline/folder-cog", "folder-cog", "folder.badge.gearshape")
    case .folderPlus: ("outline/folder-plus", "folder-plus", "folder.badge.plus")
    case .folderQuestion: ("outline/folder-question", "folder-search", "questionmark.folder")
    case .gitBranch: ("outline/git-branch", "git-branch", "arrow.triangle.branch")
    case .gitMerge: ("outline/git-merge", "git-merge", "arrow.triangle.merge")
    case .gitPullRequest: ("outline/git-pull-request", "git-pull-request", "arrow.triangle.pull")
    case .hand: ("outline/hand-stop", "hand", "hand.raised")
    case .harddrive: ("outline/database", "hard-drive", "externaldrive")
    case .hash: ("outline/hash", "hash", "number")
    case .help: ("outline/help-circle", "circle-question-mark", "questionmark.circle")
    case .history: ("outline/history", "history", "clock.arrow.circlepath")
    case .home: ("outline/home", "house", "house")
    case .inbox: ("outline/inbox", "inbox", "tray.full")
    case .info: ("outline/info-circle", "info", "info.circle")
    case .keyboard: ("outline/keyboard", "keyboard", "keyboard")
    case .layoutColumns: ("outline/layout-columns", "columns-2", "rectangle.split.2x1")
    case .layoutGrid: ("outline/layout-grid", "layout-grid", "rectangle.3.group")
    case .layoutRows: ("outline/layout-rows", "rows-2", "rectangle.split.1x2")
    case .link: ("outline/link", "link", "link")
    case .list: ("outline/list", "list", "list.bullet")
    case .lock: ("outline/lock", "lock", "lock")
    case .lockOpen: ("outline/lock-open", "lock-open", "lock.open")
    case .message: ("outline/message", "message-square", "bubble.left")
    case .messageDots: ("outline/message-dots", "message-circle-more", "ellipsis.bubble")
    case .messages: ("outline/messages", "messages-square", "bubble.left.and.text.bubble.right")
    case .microphone: ("outline/microphone", "mic", "mic")
    case .microphoneFilled: ("filled/microphone", "mic", "mic.fill")
    case .microphoneOff: ("outline/microphone-off", "mic-off", "mic.slash")
    case .minus: ("outline/minus", "minus", "minus")
    case .octagonWarning: ("filled/alert-octagon", "octagon-alert", "xmark.octagon.fill")
    case .package: ("outline/package", "package", "shippingbox")
    case .pause: ("outline/player-pause", "circle-pause", "pause.circle")
    case .pauseFilled: ("filled/player-pause", "pause+fill", "pause.fill")
    case .pencil: ("outline/pencil", "pencil", "pencil")
    case .percent: ("outline/percentage", "percent", "percent")
    case .photo: ("outline/photo", "image", "photo")
    case .pin: ("outline/pin", "pin", "pin")
    case .pinFilled: ("filled/pin", "pin+fill", "pin.fill")
    case .pinOff: ("outline/pinned-off", "pin-off", "pin.slash")
    case .playFilled: ("filled/player-play", "play+fill", "play.fill")
    case .plug: ("outline/plug", "plug", "powerplug")
    case .plus: ("outline/plus", "plus", "plus")
    case .pointer: ("outline/click", "mouse-pointer-click", "cursorarrow.click")
    case .power: ("outline/power", "power", "power")
    case .question: ("outline/question-mark", "question-mark", "questionmark")
    case .radioOn: ("outline/circle-dot", "circle-dot", "largecircle.fill.circle")
    case .record: ("outline/player-record", "disc", "record.circle")
    case .refresh: ("outline/refresh", "refresh-cw", "arrow.clockwise")
    case .rotate: ("outline/rotate", "rotate-ccw", "arrow.counterclockwise")
    case .sealCheck: ("filled/rosette-discount-check", "badge-check", "checkmark.seal.fill")
    case .search: ("outline/search", "search", "magnifyingglass")
    case .searchOff: ("outline/search-off", "search-x", "minus.magnifyingglass")
    case .send: ("outline/send", "send", "paperplane")
    case .server: ("outline/server", "server", "server.rack")
    case .settings: ("outline/settings", "settings", "gearshape")
    case .shieldCheck: ("outline/shield-check", "shield-check", "checkmark.shield")
    case .sidebar: ("outline/layout-sidebar", "panel-left", "sidebar.left")
    case .sidebarRight: ("outline/layout-sidebar-right", "panel-right", "sidebar.trailing")
    case .sleep: ("outline/zzz", "moon", "moon.zzz.fill")
    case .sliders: ("outline/adjustments-horizontal", "sliders-horizontal", "slider.horizontal.3")
    case .sparkles: ("outline/sparkles", "sparkles", "sparkles")
    case .stack: ("outline/stack-2", "layers", "square.stack.3d.up")
    case .star: ("outline/star", "star", "star")
    case .starFilled: ("filled/star", "star+fill", "star.fill")
    case .stethoscope: ("outline/stethoscope", "stethoscope", "stethoscope")
    case .stopCircle: ("outline/player-stop", "circle-stop", "stop.circle")
    case .stopFilled: ("filled/player-stop", "square+fill", "stop.fill")
    case .sum: ("outline/sum", "sigma", "sum")
    case .table: ("outline/table", "table", "tablecells")
    case .terminal: ("outline/terminal", "terminal", "terminal")
    case .timer: ("outline/clock-hour-4", "timer", "timer")
    case .tool: ("outline/tool", "wrench", "wrench.and.screwdriver")
    case .trash: ("outline/trash", "trash-2", "trash")
    case .typography: ("outline/typography", "type", "textformat")
    case .undo: ("outline/arrow-back-up", "undo-2", "arrow.uturn.backward")
    case .user: ("outline/user", "user", "person")
    case .users: ("outline/users", "users", "person.2")
    case .warning: ("outline/alert-triangle", "triangle-alert", "exclamationmark.triangle")
    case .warningFilled: ("filled/alert-triangle", "triangle-alert", "exclamationmark.triangle.fill")
    case .waveform: ("outline/wave-sine", "audio-waveform", "waveform")
    case .world: ("outline/world", "globe", "globe")
    }
}
