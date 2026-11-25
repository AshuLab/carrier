import AppKit
import CarrierCore
import SwiftUI

/// What the Engine page shows and changes of `orchestratorProfile` (CarrierCore/EngineIdentity.swift): read from `engine.json` each time the page
/// appears, the file changes or the app comes back to the front, sent to the engine as the person chooses (`setOrchestratorProfile`, which writes the file and runs on it), then read back.
@MainActor final class EngineIdentityStore: ObservableObject {
    @Published private(set) var identity: EngineIdentity?
    @Published private(set) var failure: String?

    /// Read at once, so a readable file is never shown as unreadable before the page appears.
    init() { load() }

    func load() { identity = currentConfig().flatMap { EngineIdentity(config: $0) } }

    /// nil is the default, which takes the key out of the file. What the engine answers to running on it is `ReloadNote`'s.
    func choose(_ name: String?) {
        Task {
            failure = await saveToEngine(.orchestratorProfile(name)).problem
            // the failure is the row's problem, which is not read aloud by itself
            if let failure { AccessibilityNotification.Announcement(failure).post() }
            load()
        }
    }
}
