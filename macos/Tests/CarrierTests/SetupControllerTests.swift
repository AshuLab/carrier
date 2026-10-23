import CarrierCore
import Foundation
import Testing
@testable import Carrier

private func store() -> SetupStore {
    let suite = "carrier-test-\(UUID().uuidString)"
    return SetupStore(defaults: UserDefaults(suiteName: suite)!)
}

private let saved = SetupSettings(
    carrier: "/old/carrier", node: "/old/node", path: "/old/bin", configPath: "/home/.carrier/config.json"
)

@MainActor @Test func detectAgainRunsTheDetectionAndTheRowsUpdate() async {
    let store = store()
    store.save(saved)
    let controller = SetupController(store: store, detector: {
        Detection(carrier: "/new/carrier", node: "/new/node", path: "/new/bin:/usr/bin")
    })
    await withCheckedContinuation { done in controller.detect { done.resume() } }
    let tab = engineTab(controller.settings, detecting: controller.detecting, home: "/nobody")
    #expect(tab.rows.first?.value == "/new/carrier")
    #expect(tab.rows[1].value == "/new/node")
    #expect(tab.banner.state == .ready)
    // the config path is not the shell's to say
    #expect(controller.settings.configPath == saved.configPath)
    #expect(store.load()?.carrier == "/new/carrier")
}

@MainActor @Test func detectAgainThatFindsNothingEmptiesTheToolsAndNamesThem() async {
    let store = store()
    store.save(saved)
    let controller = SetupController(store: store, detector: { Detection() })
    await withCheckedContinuation { done in controller.detect { done.resume() } }
    #expect(engineTab(controller.settings, detecting: false).banner.title == "Start Carrier needs node and carrier")
}

@MainActor @Test func aChosenPathIsStoredAndTheBannerUpdates() {
    let store = store()
    store.save(SetupSettings(node: "/n/node", path: "/bin", configPath: "/c.json"))
    let controller = SetupController(store: store, detector: { nil })
    #expect(engineTab(controller.settings, detecting: false).banner.title == "Start Carrier needs carrier")

    controller.settings[.carrier] = "/chosen/carrier"

    #expect(store.load()?.carrier == "/chosen/carrier")
    #expect(engineTab(controller.settings, detecting: false).banner.state == .ready)
}

@MainActor @Test func resetForgetsTheSavedValuesAndDetectsAgain() async {
    let store = store()
    store.save(saved)
    let controller = SetupController(store: store, detector: { Detection(carrier: "/new/carrier", node: "/new/node", path: "/new/bin") })
    await withCheckedContinuation { done in
        controller.reset { done.resume() }
        // the old values are gone at once; the shell's answer fills them in
        #expect(controller.settings.carrier.isEmpty)
        #expect(controller.detecting)
    }
    #expect(controller.detectionRuns == 1)
    #expect(store.load()?.carrier == "/new/carrier")
    #expect(store.load()?.node == "/new/node")
    #expect(store.load()?.path == "/new/bin")
}
