import AppKit
import CarrierCore
import SwiftUI

/// What the Engine page shows and writes of `orchestratorProfile` (CarrierCore/EngineIdentity.swift): read from `config.json` each time the page
/// appears, the file changes or the app comes back to the front, written in place as the person chooses, then read back.
@MainActor final class EngineIdentityStore: ObservableObject {
    @Published private(set) var identity: EngineIdentity?
    @Published private(set) var failure: String?

    func load() { identity = currentConfig().flatMap { EngineIdentity(config: $0) } }

    /// nil is the default, which takes the key out of the file.
    func choose(_ name: String?) {
        guard let data = currentConfig(), let updated = applyingOrchestratorProfile(name, to: data) else {
            failure = "The config file could not be read."
            load()
            return
        }
        do {
            try writeCurrentConfig(updated)
            failure = nil
        } catch {
            FileHandle.standardError.write(Data("carrier: saving \(configFilePath()) failed: \(error)\n".utf8))
            failure = "Could not save the config file: \(error.localizedDescription)"
        }
        load()
    }
}
