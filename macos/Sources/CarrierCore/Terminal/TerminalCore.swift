import Foundation

/// Owns a group of terminal tabs inside Carrier: a chat session drawer, an epic Continue-in-Terminal drawer, or a standalone Terminal sidebar group.
public enum TerminalOwner: Hashable, Codable, Sendable {
    case session(String)
    case epic(repo: String, issue: Int)
    case terminal(UUID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case sessionId
        case repo
        case issue
        case terminalId
    }

    private enum Kind: String, Codable {
        case session
        case epic
        case terminal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .session:
            self = .session(try container.decode(String.self, forKey: .sessionId))
        case .epic:
            self = .epic(
                repo: try container.decode(String.self, forKey: .repo),
                issue: try container.decode(Int.self, forKey: .issue)
            )
        case .terminal:
            self = .terminal(try container.decode(UUID.self, forKey: .terminalId))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .session(let id):
            try container.encode(Kind.session, forKey: .kind)
            try container.encode(id, forKey: .sessionId)
        case .epic(let repo, let issue):
            try container.encode(Kind.epic, forKey: .kind)
            try container.encode(repo, forKey: .repo)
            try container.encode(issue, forKey: .issue)
        case .terminal(let id):
            try container.encode(Kind.terminal, forKey: .kind)
            try container.encode(id, forKey: .terminalId)
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

    /// The name a pane is stored under until its shell names it. State, not words: what a person reads for it is `displayTitle`, which says the folder's name or `Copy.terminalDefaultTitle`.
    public static let untitled = "Terminal"

    public init(
        id: UUID = UUID(),
        title: String = TerminalPane.untitled,
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
    public func displayTitle(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        if let customTitle = Self.cleanCustomTitle(customTitle) { return customTitle }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false && trimmed != Self.untitled { return trimmed }
        let folder = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return folder.isEmpty == false ? folder : Copy.terminalDefaultTitle(bundle: bundle, locale: locale)
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
            title: title ?? spec.title ?? TerminalPane.untitled,
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

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        if let customTitle = TerminalPane.cleanCustomTitle(customTitle) { return customTitle }
        return activePane?.displayTitle(bundle: bundle, locale: locale) ?? Copy.terminalDefaultTitle(bundle: bundle, locale: locale)
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
