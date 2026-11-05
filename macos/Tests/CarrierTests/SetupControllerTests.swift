import CarrierCore
import Foundation
import Testing
@testable import Carrier

private func store() -> SetupStore {
    let suite = "carrier-test-\(UUID().uuidString)"
    return SetupStore(defaults: UserDefaults(suiteName: suite)!)
}

private let saved = SetupSettings(node: "/old/node", path: "/old/bin")

@MainActor @Test func detectAgainRunsTheDetectionAndNodeAndThePathUpdate() async {
    let store = store()
    store.save(saved)
    let controller = SetupController(store: store, detector: {
        Detection(node: "/new/node", path: "/new/bin:/usr/bin")
    })
    await withCheckedContinuation { done in controller.detect { done.resume() } }
    #expect(controller.settings == SetupSettings(node: "/new/node", path: "/new/bin:/usr/bin"))
    #expect(store.load()?.node == "/new/node")
}

@MainActor @Test func aChosenCarrierIsStoredAndTrimmedWhenLookedUp() {
    let store = store()
    let controller = SetupController(store: store, detector: { nil })
    controller.carrierOverride = "  /chosen/main.ts "
    #expect(store.carrierOverride == "  /chosen/main.ts ")
    #expect(controller.carrier == "/chosen/main.ts")
    // a script needs a node: none was found
    #expect(controller.missing == ["node"])
    controller.settings.node = "/n/node"
    #expect(controller.missing.isEmpty)
}
