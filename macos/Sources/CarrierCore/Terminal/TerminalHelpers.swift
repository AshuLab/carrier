import Foundation

/// Default OS directory check verifying the path exists as a directory and is readable/traversable.
public func isAccessibleTerminalDirectory(_ path: String) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
        return false
    }
    return access(path, R_OK | X_OK) == 0
}

/// Resolves a launch directory safely: trimmed `preferred` if it exists as an accessible directory, else `fallback`.
public func resolveWorkingDirectory(
    _ preferred: String?,
    fallback: String = NSHomeDirectory(),
    directoryExists: (String) -> Bool = isAccessibleTerminalDirectory
) -> String {
    if let trimmed = preferred?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false {
        let expanded = (trimmed as NSString).expandingTildeInPath
        if directoryExists(expanded) { return expanded }
    }
    return fallback
}

/// Policy gate for terminal link activation (`TerminalViewState.onOpenURL`).
public func isAllowedTerminalURL(_ raw: String) -> Bool {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https",
          let host = url.host,
          host.isEmpty == false,
          url.user == nil,
          url.password == nil
    else {
        return false
    }
    return true
}

/// Abbreviates a folder path for terminal chrome by replacing the user's home directory prefix with `~`.
public func abbreviatedTerminalPath(_ path: String, home: String = NSHomeDirectory()) -> String {
    let trimmedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
    guard trimmedHome.isEmpty == false else { return path }
    if path == trimmedHome { return "~" }
    if path.hasPrefix(trimmedHome + "/") {
        return "~" + path.dropFirst(trimmedHome.count)
    }
    return path
}

/// Toolbar subtitle for the Terminal home view, matching `Sessions`.
public func terminalsSubtitle(count: Int, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    Copy.terminalsSubtitle(count: count, bundle: bundle, locale: locale)
}

/// One standalone terminal group listed in the sidebar/home, owning one or more tabs.
public struct StandaloneTerminalSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let tabs: [TerminalTab]
    public let activeTab: TerminalTab

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String { activeTab.title(bundle: bundle, locale: locale) }
    public var workingDirectory: String { activeTab.workingDirectory }
    public var tabCount: Int { tabs.count }
    public var totalPaneCount: Int { tabs.reduce(0) { $0 + $1.paneCount } }

    /// Tab and pane counts joined with `·`, or `nil` for a single-tab single-pane terminal.
    public func countsSummary(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        var parts: [String] = []
        if tabCount > 1 {
            parts.append(Copy.terminalTabsCount(count: tabCount, bundle: bundle, locale: locale))
        }
        if totalPaneCount > tabCount {
            parts.append(Copy.terminalPanesCount(count: totalPaneCount, bundle: bundle, locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Abbreviated working directory optionally suffixed with multi-tab or multi-pane counts.
    public func subtitle(home: String = NSHomeDirectory(), bundle: Bundle? = nil, locale: Locale = .current) -> String {
        let path = abbreviatedTerminalPath(workingDirectory, home: home)
        if let countsSummary = countsSummary(bundle: bundle, locale: locale) {
            return "\(path) · \(countsSummary)"
        }
        return path
    }

    public init(id: UUID, tabs: [TerminalTab], activeTab: TerminalTab) {
        self.id = id
        self.tabs = tabs
        self.activeTab = activeTab
    }
}

/// Filters standalone terminal groups by active title, folder, or any contained tab/pane title or folder, the titles said in the language of `bundle` and `locale`.
public func filteredStandaloneTerminals(
    _ terminals: [StandaloneTerminalSummary], query: String, bundle: Bundle? = nil, locale: Locale = .current
) -> [StandaloneTerminalSummary] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return terminals }
    return terminals.filter { summary in
        summary.tabs.contains { tab in
            tab.title(bundle: bundle, locale: locale).localizedCaseInsensitiveContains(trimmed)
                || tab.workingDirectory.localizedCaseInsensitiveContains(trimmed)
                || tab.orderedPanes.contains { $0.displayTitle(bundle: bundle, locale: locale).localizedCaseInsensitiveContains(trimmed) }
        }
    }
}

/// Drop target zone computed when dragging one terminal pane onto another.
public enum TerminalDropZone: Equatable, Sendable {
    case edge(SplitEdge)
    case swap
}

/// Maps pointer coordinates within a pane rect of size `(width, height)` into a split-edge move or center swap.
public func terminalDropZone(x: Double, y: Double, width: Double, height: Double) -> TerminalDropZone {
    guard width > 0, height > 0 else { return .swap }
    let nx = min(max(x / width, 0), 1)
    let ny = min(max(y / height, 0), 1)
    let margin = 0.25
    let leftDist = nx
    let rightDist = 1 - nx
    let topDist = ny
    let bottomDist = 1 - ny
    let best = min(leftDist, rightDist, topDist, bottomDist)
    guard best <= margin else { return .swap }
    if best == leftDist { return .edge(.leading) }
    if best == rightDist { return .edge(.trailing) }
    if best == topDist { return .edge(.top) }
    return .edge(.bottom)
}
