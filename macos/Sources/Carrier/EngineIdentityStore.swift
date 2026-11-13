import AppKit
import CarrierCore
import SwiftUI

/// What the Engine page shows and writes of `orchestratorProfile` (CarrierCore/EngineIdentity.swift): read from `config.json` each time the page
/// appears, the file changes or the app comes back to the front, written as the person chooses (and the engine asked to reload), then read back.
@MainActor final class EngineIdentityStore: ObservableObject {
    @Published private(set) var identity: EngineIdentity?
    @Published private(set) var failure: String?

    /// Read at once, so a readable file is never shown as unreadable before the page appears.
    init() { load() }

    func load() { identity = currentConfig().flatMap { EngineIdentity(config: $0) } }

    /// nil is the default, which takes the key out of the file. The engine is asked to reload after the write; what it answers is `ReloadNote`'s.
    func choose(_ name: String?) {
        failure = saveOrchestratorProfile(name, path: configFilePath()).problem
        load()
    }
}
