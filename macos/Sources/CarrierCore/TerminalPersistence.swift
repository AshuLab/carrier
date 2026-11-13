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
        let strippedWorkspaces = workspaces.map { workspace in
            TerminalWorkspace(
                owner: workspace.owner,
                tabs: workspace.tabs.map { tab in
                    var copy = tab
                    for paneId in copy.panes.keys {
                        copy.panes[paneId]?.envVars = [:]
                    }
                    return copy
                },
                activeTabId: workspace.activeTabId
            )
        }
        return PersistedTerminalWorkspace(
            schemaVersion: PersistedTerminalWorkspace.currentSchemaVersion,
            workspaces: strippedWorkspaces
        )
    }

    init(
        restoring persisted: PersistedTerminalWorkspace,
        knownSessionIds: Set<String>? = nil,
        fallbackDirectory: String = NSHomeDirectory(),
        directoryExists: (String) -> Bool = isAccessibleTerminalDirectory
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
                        envVars: [:],
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

/// Reason a persisted `terminals.json` snapshot could not be loaded.
public enum TerminalWorkspaceLoadRejection: Equatable, Sendable {
    case unreadable
    case corrupt(backedUp: Bool)
    case unsupportedSchema(Int)
}

/// Outcome of reading `<Carrier folder>/app/terminals.json` at launch.
public enum TerminalWorkspaceLoadResult: Equatable, Sendable {
    case missing
    case loaded(PersistedTerminalWorkspace)
    case rejected(TerminalWorkspaceLoadRejection)
}

/// Pure file-store seam for saving and restoring `PersistedTerminalWorkspace`.
/// Pass `fileURL: nil` to disable disk I/O during `--fixture`, `--selftest`, or in-memory tests.
public struct TerminalWorkspaceFileStore: Sendable {
    public let fileURL: URL?
    private let log: @Sendable (String) -> Void
    private let now: @Sendable () -> Date

    public init(
        fileURL: URL?,
        log: @escaping @Sendable (String) -> Void = { FileHandle.standardError.write(Data("carrier: \($0)\n".utf8)) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileURL = fileURL
        self.log = log
        self.now = now
    }

    public func load() -> PersistedTerminalWorkspace? {
        guard case .loaded(let workspace) = loadResult() else { return nil }
        return workspace
    }

    public func loadResult() -> TerminalWorkspaceLoadResult {
        guard let fileURL else { return .missing }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .missing
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            log("could not read terminal workspace at \(fileURL.path): \(error.localizedDescription)")
            return .rejected(.unreadable)
        }
        let decoded: PersistedTerminalWorkspace
        do {
            decoded = try JSONDecoder().decode(PersistedTerminalWorkspace.self, from: data)
        } catch {
            let reason = error.localizedDescription
            if let backupURL = backupCorruptWorkspace(at: fileURL) {
                log("could not decode terminal workspace at \(fileURL.path): \(reason); moved corrupt file to \(backupURL.lastPathComponent)")
                return .rejected(.corrupt(backedUp: true))
            }
            log("could not decode terminal workspace at \(fileURL.path): \(reason)")
            return .rejected(.corrupt(backedUp: false))
        }
        guard decoded.schemaVersion == PersistedTerminalWorkspace.currentSchemaVersion else {
            log("ignoring terminal workspace at \(fileURL.path) with unsupported schemaVersion \(decoded.schemaVersion)")
            return .rejected(.unsupportedSchema(decoded.schemaVersion))
        }
        return .loaded(decoded)
    }

    @discardableResult
    public func save(_ persisted: PersistedTerminalWorkspace) -> Bool {
        guard let fileURL else { return false }
        let sanitized = PersistedTerminalWorkspace(
            schemaVersion: persisted.schemaVersion,
            workspaces: persisted.workspaces.map { workspace in
                TerminalWorkspace(
                    owner: workspace.owner,
                    tabs: workspace.tabs.map { tab in
                        var copy = tab
                        for paneId in copy.panes.keys {
                            copy.panes[paneId]?.envVars = [:]
                        }
                        return copy
                    },
                    activeTabId: workspace.activeTabId
                )
            }
        )
        do {
            let folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: folder,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(sanitized)
            let tempURL = folder.appendingPathComponent(".\(fileURL.lastPathComponent).tmp.\(UUID().uuidString)")
            do {
                try Self.writeExclusivePrivateFile(data, to: tempURL)
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                throw error
            }
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            } catch {
                log("saved terminal workspace at \(fileURL.path), but failed to confirm 0600 permissions: \(error.localizedDescription)")
            }
            return true
        } catch {
            log("could not save terminal workspace at \(fileURL.path): \(error.localizedDescription)")
            return false
        }
    }

    public func removeFile() {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            log("could not remove terminal workspace at \(fileURL.path): \(error.localizedDescription)")
        }
    }

    private func backupCorruptWorkspace(at fileURL: URL) -> URL? {
        let folder = fileURL.deletingLastPathComponent()
        let stamp = Int(now().timeIntervalSince1970)
        var candidate = folder.appendingPathComponent("\(fileURL.lastPathComponent).bak.\(stamp)")
        if FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(fileURL.lastPathComponent).bak.\(stamp).\(UUID().uuidString.prefix(8))")
        }
        do {
            try FileManager.default.moveItem(at: fileURL, to: candidate)
            return candidate
        } catch {
            log("could not back up corrupt terminal workspace at \(fileURL.path): \(error.localizedDescription)")
            return nil
        }
    }

    private static func writeExclusivePrivateFile(_ data: Data, to url: URL) throws {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        // Enforce 0600 even if process umask restricted or altered creation bits.
        _ = fchmod(fd, 0o600)
        try handle.write(contentsOf: data)
    }
}
