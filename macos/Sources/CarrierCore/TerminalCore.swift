import Foundation

/// Owns a group of terminal tabs inside Carrier: either a chat session or the standalone quick terminal drawer.
public enum TerminalOwner: Hashable, Codable, Sendable {
    case session(String)
    case quick

    private enum CodingKeys: String, CodingKey {
        case kind
        case sessionId
    }

    private enum Kind: String, Codable {
        case session
        case quick
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .session:
            self = .session(try container.decode(String.self, forKey: .sessionId))
        case .quick:
            self = .quick
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .session(let id):
            try container.encode(Kind.session, forKey: .kind)
            try container.encode(id, forKey: .sessionId)
        case .quick:
            try container.encode(Kind.quick, forKey: .kind)
        }
    }
}

/// Parameters for launching one interactive shell pane.
public struct TerminalLaunchSpec: Equatable, Codable, Sendable {
    public var workingDirectory: String
    public var envVars: [String: String]
    public var command: String?
    public var waitAfterCommand: Bool
    public var title: String?
    public var customTitle: String?

    public init(
        workingDirectory: String,
        envVars: [String: String] = [:],
        command: String? = nil,
        waitAfterCommand: Bool = false,
        title: String? = nil,
        customTitle: String? = nil
    ) {
        self.workingDirectory = workingDirectory
        self.envVars = envVars
        self.command = command
        self.waitAfterCommand = waitAfterCommand
        self.title = title
        self.customTitle = customTitle
    }
}

/// One live shell leaf inside a tab's split layout.
public struct TerminalPane: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var customTitle: String?
    public var workingDirectory: String
    public var envVars: [String: String]
    public var command: String?
    public var waitAfterCommand: Bool

    public init(
        id: UUID = UUID(),
        title: String = "Terminal",
        customTitle: String? = nil,
        workingDirectory: String,
        envVars: [String: String] = [:],
        command: String? = nil,
        waitAfterCommand: Bool = false
    ) {
        self.id = id
        self.title = title
        self.customTitle = Self.cleanCustomTitle(customTitle)
        self.workingDirectory = workingDirectory
        self.envVars = envVars
        self.command = command
        self.waitAfterCommand = waitAfterCommand
    }

    /// Preferred label for chrome: explicit rename first, then live shell/OSC title, then folder basename.
    public var displayTitle: String {
        if let customTitle = Self.cleanCustomTitle(customTitle) { return customTitle }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false && trimmed != "Terminal" { return trimmed }
        let folder = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return folder.isEmpty == false ? folder : (trimmed.isEmpty ? "Terminal" : trimmed)
    }

    static func cleanCustomTitle(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }
}

/// One tab owned by a `TerminalOwner`, containing one or more split `TerminalPane` leaves.
public struct TerminalTab: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var owner: TerminalOwner
    public var customTitle: String?
    public var root: SplitNode
    public var panes: [UUID: TerminalPane]
    public var activePaneId: UUID
    public var zoomedPaneId: UUID?

    public init(
        id: UUID = UUID(),
        owner: TerminalOwner,
        root: SplitNode,
        panes: [UUID: TerminalPane],
        activePaneId: UUID,
        customTitle: String? = nil,
        zoomedPaneId: UUID? = nil
    ) {
        self.id = id
        self.owner = owner
        self.customTitle = TerminalPane.cleanCustomTitle(customTitle)
        self.root = root
        self.panes = panes
        self.activePaneId = activePaneId
        self.zoomedPaneId = zoomedPaneId
        normalize()
    }

    public init(
        id: UUID = UUID(),
        owner: TerminalOwner,
        spec: TerminalLaunchSpec,
        paneId: UUID = UUID(),
        title: String? = nil
    ) {
        let pane = TerminalPane(
            id: paneId,
            title: title ?? spec.title ?? "Terminal",
            customTitle: spec.customTitle,
            workingDirectory: spec.workingDirectory,
            envVars: spec.envVars,
            command: spec.command,
            waitAfterCommand: spec.waitAfterCommand
        )
        self.init(
            id: id,
            owner: owner,
            root: .leaf(paneId),
            panes: [paneId: pane],
            activePaneId: paneId
        )
    }

    public var orderedPaneIds: [UUID] { root.leafPaneIds }

    public var orderedPanes: [TerminalPane] {
        orderedPaneIds.compactMap { panes[$0] }
    }

    public var activePane: TerminalPane? {
        panes[activePaneId]
    }

    public var paneCount: Int { panes.count }

    public var workingDirectory: String {
        activePane?.workingDirectory ?? orderedPanes.first?.workingDirectory ?? ""
    }

    public var title: String {
        if let customTitle = TerminalPane.cleanCustomTitle(customTitle) { return customTitle }
        return activePane?.displayTitle ?? "Terminal"
    }

    mutating func normalize() {
        let validIds = Set(panes.keys)
        if let cleanRoot = root.normalized(validPaneIds: validIds) {
            root = cleanRoot
        } else if let firstId = panes.keys.min(by: { $0.uuidString < $1.uuidString }) {
            root = .leaf(firstId)
        }
        let leafIds = Set(root.leafPaneIds)
        panes = panes.filter { leafIds.contains($0.key) }
        if panes[activePaneId] == nil, let fallback = root.leafPaneIds.first {
            activePaneId = fallback
        }
        if panes.count <= 1 {
            zoomedPaneId = nil
        } else if let zoomed = zoomedPaneId, panes[zoomed] == nil {
            zoomedPaneId = nil
        }
    }
}

/// Ordered tab state for one owner.
public struct TerminalWorkspace: Equatable, Codable, Sendable {
    public var owner: TerminalOwner
    public var tabs: [TerminalTab]
    public var activeTabId: UUID?

    public init(owner: TerminalOwner, tabs: [TerminalTab], activeTabId: UUID?) {
        self.owner = owner
        self.tabs = tabs
        self.activeTabId = activeTabId
    }
}

/// Pure workspace registry managing owners, multi-tab state, split pane trees, pane moves, and focus transitions.
public struct TerminalRegistry: Equatable, Sendable {
    public private(set) var tabsById: [UUID: TerminalTab] = [:]
    public private(set) var orderByOwner: [TerminalOwner: [UUID]] = [:]
    public private(set) var activeTabByOwner: [TerminalOwner: UUID] = [:]

    public init() {}

    public var owners: [TerminalOwner] {
        Array(orderByOwner.keys)
    }

    public var allTabs: [TerminalTab] {
        orderByOwner.values.flatMap { $0.compactMap { tabsById[$0] } }
    }

    public var allPaneIds: [UUID] {
        allTabs.flatMap(\.orderedPaneIds)
    }

    public func tabs(for owner: TerminalOwner) -> [TerminalTab] {
        (orderByOwner[owner] ?? []).compactMap { tabsById[$0] }
    }

    public func activeTabId(for owner: TerminalOwner) -> UUID? {
        activeTabByOwner[owner]
    }

    public func activeTab(for owner: TerminalOwner) -> TerminalTab? {
        activeTabByOwner[owner].flatMap { tabsById[$0] }
    }

    public func activePane(for owner: TerminalOwner) -> TerminalPane? {
        activeTab(for: owner)?.activePane
    }

    public func tab(id tabId: UUID) -> TerminalTab? {
        tabsById[tabId]
    }

    public func pane(id paneId: UUID) -> TerminalPane? {
        guard let location = location(ofPaneId: paneId) else { return nil }
        return tabsById[location.tabId]?.panes[paneId]
    }

    public func location(ofPaneId paneId: UUID) -> (owner: TerminalOwner, tabId: UUID)? {
        for (owner, tabIds) in orderByOwner {
            for tabId in tabIds {
                if let tab = tabsById[tabId], tab.panes[paneId] != nil {
                    return (owner, tabId)
                }
            }
        }
        return nil
    }

    public func allPaneIds(for owner: TerminalOwner) -> [UUID] {
        tabs(for: owner).flatMap(\.orderedPaneIds)
    }

    public var workspaces: [TerminalWorkspace] {
        orderByOwner.keys.sorted(by: ownerSortOrder).map { owner in
            TerminalWorkspace(
                owner: owner,
                tabs: tabs(for: owner),
                activeTabId: activeTabByOwner[owner]
            )
        }
    }

    // MARK: - Tab Lifecycle & Ordering

    @discardableResult
    public mutating func openTab(
        owner: TerminalOwner,
        spec: TerminalLaunchSpec,
        id: UUID = UUID(),
        paneId: UUID = UUID(),
        title: String? = nil,
        activate: Bool = true
    ) -> TerminalTab {
        let tab = TerminalTab(id: id, owner: owner, spec: spec, paneId: paneId, title: title)
        insertTab(tab, at: nil, activate: activate)
        return tab
    }

    public mutating func selectTab(id: UUID, for owner: TerminalOwner? = nil) {
        guard let tab = tabsById[id] else { return }
        if let owner, tab.owner != owner { return }
        activeTabByOwner[tab.owner] = id
    }

    @discardableResult
    public mutating func moveTab(id: UUID, toIndex requestedIndex: Int) -> Bool {
        guard let tab = tabsById[id], var order = orderByOwner[tab.owner], let current = order.firstIndex(of: id) else {
            return false
        }
        order.remove(at: current)
        let bounded = min(max(requestedIndex, 0), order.count)
        order.insert(id, at: bounded)
        orderByOwner[tab.owner] = order
        return true
    }

    @discardableResult
    public mutating func moveTab(
        id: UUID,
        toOwner destinationOwner: TerminalOwner,
        atIndex requestedIndex: Int? = nil,
        activate: Bool = true
    ) -> Bool {
        guard var tab = tabsById[id] else { return false }
        if tab.owner == destinationOwner {
            if let requestedIndex { return moveTab(id: id, toIndex: requestedIndex) }
            if activate { activeTabByOwner[destinationOwner] = id }
            return true
        }
        removeTabEntryOnly(id: id, from: tab.owner)
        tab.owner = destinationOwner
        insertTab(tab, at: requestedIndex, activate: activate)
        return true
    }

    @discardableResult
    public mutating func closeTab(id: UUID) -> TerminalTab? {
        guard let removed = tabsById[id] else { return nil }
        removeTabEntryOnly(id: id, from: removed.owner)
        return removed
    }

    @discardableResult
    public mutating func closeAll(for owner: TerminalOwner) -> [TerminalTab] {
        let removed = tabs(for: owner)
        for tab in removed {
            tabsById.removeValue(forKey: tab.id)
        }
        orderByOwner.removeValue(forKey: owner)
        activeTabByOwner.removeValue(forKey: owner)
        return removed
    }

    // MARK: - Split Panes & Intra/Inter-Tab Moves

    @discardableResult
    public mutating func splitPane(
        _ targetPaneId: UUID,
        edge: SplitEdge,
        spec: TerminalLaunchSpec? = nil,
        newPaneId: UUID = UUID(),
        ratio: Double = 0.5,
        activate: Bool = true
    ) -> TerminalPane? {
        guard pane(id: newPaneId) == nil, let loc = location(ofPaneId: targetPaneId), var tab = tabsById[loc.tabId] else {
            return nil
        }
        guard let targetPane = tab.panes[targetPaneId] else { return nil }
        guard let nextRoot = tab.root.inserting(newPaneId, nextTo: targetPaneId, edge: edge, ratio: ratio) else {
            return nil
        }
        let resolvedCwd = spec?.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let cwd = (resolvedCwd?.isEmpty == false ? resolvedCwd! : targetPane.workingDirectory)
        let pane = TerminalPane(
            id: newPaneId,
            title: spec?.title ?? "Terminal",
            customTitle: spec?.customTitle,
            workingDirectory: cwd,
            envVars: spec?.envVars ?? [:],
            command: spec?.command,
            waitAfterCommand: spec?.waitAfterCommand ?? false
        )
        tab.root = nextRoot
        tab.panes[newPaneId] = pane
        tab.zoomedPaneId = nil
        if activate {
            tab.activePaneId = newPaneId
            activeTabByOwner[tab.owner] = tab.id
        }
        tab.normalize()
        tabsById[tab.id] = tab
        return pane
    }

    public mutating func selectPane(id paneId: UUID) {
        guard let loc = location(ofPaneId: paneId), var tab = tabsById[loc.tabId] else { return }
        tab.activePaneId = paneId
        if let zoomed = tab.zoomedPaneId, zoomed != paneId {
            tab.zoomedPaneId = nil
        }
        tabsById[tab.id] = tab
        activeTabByOwner[loc.owner] = tab.id
    }

    @discardableResult
    public mutating func closePane(id paneId: UUID) -> (removedPane: TerminalPane, closedTabId: UUID?)? {
        guard let loc = location(ofPaneId: paneId), var tab = tabsById[loc.tabId], let pane = tab.panes[paneId] else {
            return nil
        }
        if tab.panes.count <= 1 {
            _ = closeTab(id: tab.id)
            return (pane, tab.id)
        }
        let siblingFallback = tab.root.sibling(of: paneId)
        let removal = tab.root.removing(paneId)
        guard removal.removed, let nextRoot = removal.node else {
            _ = closeTab(id: tab.id)
            return (pane, tab.id)
        }
        tab.root = nextRoot
        tab.panes.removeValue(forKey: paneId)
        if tab.activePaneId == paneId {
            tab.activePaneId = siblingFallback ?? nextRoot.leafPaneIds[0]
        }
        if tab.zoomedPaneId == paneId || tab.panes.count <= 1 {
            tab.zoomedPaneId = nil
        }
        tab.normalize()
        tabsById[tab.id] = tab
        return (pane, nil)
    }

    public mutating func setSplitRatio(inTab tabId: UUID, at path: [SplitBranch], ratio: Double) {
        guard var tab = tabsById[tabId] else { return }
        tab.root = tab.root.settingRatio(at: path, ratio: ratio)
        tabsById[tabId] = tab
    }

    public mutating func equalizeSplits(inTab tabId: UUID) {
        guard var tab = tabsById[tabId] else { return }
        tab.root = tab.root.equalized()
        tabsById[tabId] = tab
    }

    public mutating func toggleZoom(paneId: UUID) {
        guard let loc = location(ofPaneId: paneId), var tab = tabsById[loc.tabId] else { return }
        guard tab.panes.count > 1 else {
            tab.zoomedPaneId = nil
            tabsById[tab.id] = tab
            return
        }
        tab.activePaneId = paneId
        tab.zoomedPaneId = tab.zoomedPaneId == paneId ? nil : paneId
        tabsById[tab.id] = tab
        activeTabByOwner[loc.owner] = tab.id
    }

    @discardableResult
    public mutating func movePane(
        _ sourcePaneId: UUID,
        toTarget targetPaneId: UUID,
        edge: SplitEdge,
        ratio: Double = 0.5
    ) -> Bool {
        guard sourcePaneId != targetPaneId,
              let sourceLoc = location(ofPaneId: sourcePaneId),
              let targetLoc = location(ofPaneId: targetPaneId),
              let sourcePane = tabsById[sourceLoc.tabId]?.panes[sourcePaneId]
        else {
            return false
        }

        if sourceLoc.tabId == targetLoc.tabId {
            guard var tab = tabsById[sourceLoc.tabId], tab.panes.count > 1 else { return false }
            let removed = tab.root.removing(sourcePaneId)
            guard removed.removed, let shrunkRoot = removed.node else { return false }
            guard let expandedRoot = shrunkRoot.inserting(sourcePaneId, nextTo: targetPaneId, edge: edge, ratio: ratio) else {
                return false
            }
            tab.root = expandedRoot
            tab.activePaneId = sourcePaneId
            tab.zoomedPaneId = nil
            tab.normalize()
            tabsById[tab.id] = tab
            activeTabByOwner[tab.owner] = tab.id
            return true
        }

        // Remove from source tab first so the unique leaf invariant holds globally.
        guard closePane(id: sourcePaneId) != nil else { return false }
        guard var targetTab = tabsById[targetLoc.tabId] else { return false }
        guard let expandedRoot = targetTab.root.inserting(sourcePaneId, nextTo: targetPaneId, edge: edge, ratio: ratio) else {
            return false
        }
        targetTab.root = expandedRoot
        targetTab.panes[sourcePaneId] = sourcePane
        targetTab.activePaneId = sourcePaneId
        targetTab.zoomedPaneId = nil
        targetTab.normalize()
        tabsById[targetTab.id] = targetTab
        activeTabByOwner[targetLoc.owner] = targetTab.id
        return true
    }

    @discardableResult
    public mutating func swapPanes(_ firstPaneId: UUID, _ secondPaneId: UUID) -> Bool {
        guard firstPaneId != secondPaneId,
              let firstLoc = location(ofPaneId: firstPaneId),
              let secondLoc = location(ofPaneId: secondPaneId),
              var firstTab = tabsById[firstLoc.tabId],
              var secondTab = tabsById[secondLoc.tabId],
              let firstPane = firstTab.panes[firstPaneId],
              let secondPane = secondTab.panes[secondPaneId]
        else {
            return false
        }

        if firstLoc.tabId == secondLoc.tabId {
            firstTab.root = firstTab.root.swapping(firstPaneId, secondPaneId)
            if firstTab.activePaneId == firstPaneId {
                firstTab.activePaneId = secondPaneId
            } else if firstTab.activePaneId == secondPaneId {
                firstTab.activePaneId = firstPaneId
            }
            firstTab.zoomedPaneId = nil
            firstTab.normalize()
            tabsById[firstTab.id] = firstTab
            return true
        }

        firstTab.root = replaceLeaf(firstTab.root, old: firstPaneId, new: secondPaneId)
        secondTab.root = replaceLeaf(secondTab.root, old: secondPaneId, new: firstPaneId)
        firstTab.panes.removeValue(forKey: firstPaneId)
        firstTab.panes[secondPaneId] = secondPane
        secondTab.panes.removeValue(forKey: secondPaneId)
        secondTab.panes[firstPaneId] = firstPane
        if firstTab.activePaneId == firstPaneId { firstTab.activePaneId = secondPaneId }
        if secondTab.activePaneId == secondPaneId { secondTab.activePaneId = firstPaneId }
        firstTab.zoomedPaneId = nil
        secondTab.zoomedPaneId = nil
        firstTab.normalize()
        secondTab.normalize()
        tabsById[firstTab.id] = firstTab
        tabsById[secondTab.id] = secondTab
        return true
    }

    @discardableResult
    public mutating func detachPaneToNewTab(
        _ paneId: UUID,
        toOwner targetOwner: TerminalOwner? = nil,
        atIndex requestedIndex: Int? = nil,
        newTabId: UUID = UUID(),
        activate: Bool = true
    ) -> TerminalTab? {
        guard tabsById[newTabId] == nil,
              let sourceLoc = location(ofPaneId: paneId),
              let sourceTab = tabsById[sourceLoc.tabId],
              let pane = sourceTab.panes[paneId]
        else {
            return nil
        }

        let destinationOwner = targetOwner ?? sourceLoc.owner
        if sourceTab.panes.count <= 1 {
            guard destinationOwner != sourceLoc.owner else { return nil }
            guard moveTab(id: sourceTab.id, toOwner: destinationOwner, atIndex: requestedIndex, activate: activate) else {
                return nil
            }
            return tabsById[sourceTab.id]
        }

        guard closePane(id: paneId) != nil else { return nil }
        let newTab = TerminalTab(
            id: newTabId,
            owner: destinationOwner,
            root: .leaf(paneId),
            panes: [paneId: pane],
            activePaneId: paneId
        )
        insertTab(newTab, at: requestedIndex, activate: activate)
        return newTab
    }

    // MARK: - Pane Metadata

    public mutating func updatePaneTitle(_ title: String, forPane paneId: UUID) {
        guard let loc = location(ofPaneId: paneId), var tab = tabsById[loc.tabId], var pane = tab.panes[paneId] else {
            return
        }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        pane.title = cleaned.isEmpty ? "Terminal" : cleaned
        tab.panes[paneId] = pane
        tabsById[tab.id] = tab
    }

    public mutating func renamePane(_ paneId: UUID, customTitle: String?) {
        guard let loc = location(ofPaneId: paneId), var tab = tabsById[loc.tabId], var pane = tab.panes[paneId] else {
            return
        }
        pane.customTitle = TerminalPane.cleanCustomTitle(customTitle)
        tab.panes[paneId] = pane
        tabsById[tab.id] = tab
    }

    public mutating func updatePaneWorkingDirectory(_ workingDirectory: String, forPane paneId: UUID) {
        let trimmed = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false,
              let loc = location(ofPaneId: paneId),
              var tab = tabsById[loc.tabId],
              var pane = tab.panes[paneId]
        else {
            return
        }
        pane.workingDirectory = trimmed
        tab.panes[paneId] = pane
        tabsById[tab.id] = tab
    }

    @discardableResult
    public mutating func pruneSessions(keeping knownSessionIds: Set<String>) -> [UUID] {
        var removedPaneIds: [UUID] = []
        for owner in owners {
            guard case .session(let sessionId) = owner, knownSessionIds.contains(sessionId) == false else {
                continue
            }
            for tab in closeAll(for: owner) {
                removedPaneIds.append(contentsOf: tab.orderedPaneIds)
            }
        }
        return removedPaneIds
    }

    // MARK: - Internal Helpers

    mutating func replaceContents(with cleanWorkspaces: [TerminalWorkspace]) {
        tabsById = [:]
        orderByOwner = [:]
        activeTabByOwner = [:]
        for workspace in cleanWorkspaces where workspace.tabs.isEmpty == false {
            var order = orderByOwner[workspace.owner] ?? []
            for var tab in workspace.tabs {
                tab.owner = workspace.owner
                tab.normalize()
                guard tab.panes.isEmpty == false, tabsById[tab.id] == nil else { continue }
                tabsById[tab.id] = tab
                order.append(tab.id)
            }
            guard order.isEmpty == false else { continue }
            orderByOwner[workspace.owner] = order
            if let preferredActive = workspace.activeTabId, order.contains(preferredActive) {
                activeTabByOwner[workspace.owner] = preferredActive
            } else if activeTabByOwner[workspace.owner] == nil {
                activeTabByOwner[workspace.owner] = order.first
            }
        }
    }

    private mutating func insertTab(_ tab: TerminalTab, at requestedIndex: Int?, activate: Bool) {
        var cleanTab = tab
        cleanTab.normalize()
        tabsById[cleanTab.id] = cleanTab
        var order = orderByOwner[cleanTab.owner] ?? []
        if let requestedIndex {
            let bounded = min(max(requestedIndex, 0), order.count)
            order.insert(cleanTab.id, at: bounded)
        } else {
            order.append(cleanTab.id)
        }
        orderByOwner[cleanTab.owner] = order
        if activate || activeTabByOwner[cleanTab.owner] == nil {
            activeTabByOwner[cleanTab.owner] = cleanTab.id
        }
    }

    private mutating func removeTabEntryOnly(id: UUID, from owner: TerminalOwner) {
        tabsById.removeValue(forKey: id)
        var order = orderByOwner[owner] ?? []
        guard let index = order.firstIndex(of: id) else { return }
        order.remove(at: index)
        if order.isEmpty {
            orderByOwner.removeValue(forKey: owner)
            activeTabByOwner.removeValue(forKey: owner)
        } else {
            orderByOwner[owner] = order
            if activeTabByOwner[owner] == id {
                let fallbackIndex = min(index, order.count - 1)
                activeTabByOwner[owner] = order[fallbackIndex]
            }
        }
    }

    private func replaceLeaf(_ node: SplitNode, old: UUID, new: UUID) -> SplitNode {
        switch node {
        case .leaf(let id):
            return .leaf(id == old ? new : id)
        case .split(let axis, let ratio, let first, let second):
            return .split(axis: axis, ratio: ratio, first: replaceLeaf(first, old: old, new: new), second: replaceLeaf(second, old: old, new: new))
        }
    }

    private func ownerSortOrder(_ lhs: TerminalOwner, _ rhs: TerminalOwner) -> Bool {
        switch (lhs, rhs) {
        case (.quick, .quick): return false
        case (.quick, .session): return true
        case (.session, .quick): return false
        case (.session(let a), .session(let b)): return a < b
        }
    }
}

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
