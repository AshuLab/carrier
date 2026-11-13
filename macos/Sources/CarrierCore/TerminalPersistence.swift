import Foundation

/// Canonical path for the persisted terminal workspace inside `<Carrier folder>/app/terminals.json`.
public func terminalWorkspaceURL(carrierFolder: String) -> URL {
    URL(fileURLWithPath: carrierFolder, isDirectory: true)
        .appendingPathComponent("app", isDirectory: true)
        .appendingPathComponent("terminals.json", isDirectory: false)
}

/// Versioned snapshot of all open terminal owners, tabs, split layouts, ratios, focus, and working directories.
public struct PersistedTerminalWorkspace: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var workspaces: [TerminalWorkspace]

    public init(schemaVersion: Int = Self.currentSchemaVersion, workspaces: [TerminalWorkspace]) {
        self.schemaVersion = schemaVersion
        self.workspaces = workspaces
    }
}

public extension TerminalRegistry {
    func exportPersistedWorkspace() -> PersistedTerminalWorkspace {
        PersistedTerminalWorkspace(
            schemaVersion: PersistedTerminalWorkspace.currentSchemaVersion,
            workspaces: workspaces
        )
    }

    init(
        restoring persisted: PersistedTerminalWorkspace,
        knownSessionIds: Set<String>? = nil,
        fallbackDirectory: String = NSHomeDirectory(),
        directoryExists: (String) -> Bool = { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    ) {
        self.init()
        guard persisted.schemaVersion == PersistedTerminalWorkspace.currentSchemaVersion else {
            return
        }

        let safeFallback = directoryExists(fallbackDirectory)
            ? fallbackDirectory
            : resolveWorkingDirectory(NSHomeDirectory(), fallback: NSHomeDirectory(), directoryExists: directoryExists)
        var usedTabIds: Set<UUID> = []
        var usedPaneIds: Set<UUID> = []
        var mergedWorkspacesByOwner: [TerminalOwner: TerminalWorkspace] = [:]
        var ownerOrder: [TerminalOwner] = []

        for workspace in persisted.workspaces {
            switch workspace.owner {
            case .quick:
                break
            case .session(let sessionId):
                if let knownSessionIds, knownSessionIds.contains(sessionId) == false {
                    continue
                }
            }

            var cleanTabs: [TerminalTab] = []
            for var tab in workspace.tabs {
                guard usedTabIds.insert(tab.id).inserted else { continue }
                tab.owner = workspace.owner

                var cleanPanes: [UUID: TerminalPane] = [:]
                for (paneKey, rawPane) in tab.panes {
                    guard usedPaneIds.insert(paneKey).inserted else { continue }
                    let resolvedCwd = resolveWorkingDirectory(
                        rawPane.workingDirectory,
                        fallback: safeFallback,
                        directoryExists: directoryExists
                    )
                    let canonicalPane = TerminalPane(
                        id: paneKey,
                        title: rawPane.title,
                        customTitle: rawPane.customTitle,
                        workingDirectory: resolvedCwd,
                        envVars: rawPane.envVars,
                        command: rawPane.command,
                        waitAfterCommand: rawPane.waitAfterCommand
                    )
                    cleanPanes[paneKey] = canonicalPane
                }

                guard cleanPanes.isEmpty == false else { continue }
                tab.panes = cleanPanes
                tab.normalize()
                cleanTabs.append(tab)
            }

            guard cleanTabs.isEmpty == false else { continue }
            if var existing = mergedWorkspacesByOwner[workspace.owner] {
                existing.tabs.append(contentsOf: cleanTabs)
                if existing.activeTabId == nil {
                    existing.activeTabId = workspace.activeTabId
                }
                mergedWorkspacesByOwner[workspace.owner] = existing
            } else {
                mergedWorkspacesByOwner[workspace.owner] = TerminalWorkspace(
                    owner: workspace.owner,
                    tabs: cleanTabs,
                    activeTabId: workspace.activeTabId
                )
                ownerOrder.append(workspace.owner)
            }
        }

        let cleanWorkspaces = ownerOrder.compactMap { mergedWorkspacesByOwner[$0] }
        replaceContents(with: cleanWorkspaces)
    }
}

/// Pure file-store seam for saving and restoring `PersistedTerminalWorkspace`.
/// Pass `fileURL: nil` to disable disk I/O during `--fixture`, `--selftest`, or in-memory tests.
public struct TerminalWorkspaceFileStore: Sendable {
    public let fileURL: URL?

    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    public func load() -> PersistedTerminalWorkspace? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(PersistedTerminalWorkspace.self, from: data) else {
            return nil
        }
        guard decoded.schemaVersion == PersistedTerminalWorkspace.currentSchemaVersion else {
            return nil
        }
        return decoded
    }

    @discardableResult
    public func save(_ persisted: PersistedTerminalWorkspace) -> Bool {
        guard let fileURL else { return false }
        do {
            let folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(persisted)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public func removeFile() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
