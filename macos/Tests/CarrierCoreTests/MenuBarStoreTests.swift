import Foundation
import Testing
@testable import CarrierCore

@Test func menuBarSettingsStartOnTheDefaults() {
    let store = MenuBarStore(defaults: UserDefaults(suiteName: "menubar-\(UUID().uuidString)")!)
    #expect(store.style == .countAndBar)
    #expect(store.animates)
    #expect(store.showsEpics)
}

@Test func menuBarSettingsSurviveARelaunch() {
    let name = "menubar-\(UUID().uuidString)"
    let store = MenuBarStore(defaults: UserDefaults(suiteName: name)!)
    store.style = .barOnly
    store.animates = false
    store.showsEpics = false
    let relaunched = MenuBarStore(defaults: UserDefaults(suiteName: name)!)
    #expect(relaunched.style == .barOnly)
    #expect(relaunched.animates == false)
    #expect(relaunched.showsEpics == false)
}

@Test func anUnknownSavedStyleFallsBackToTheDefault() {
    let defaults = UserDefaults(suiteName: "menubar-\(UUID().uuidString)")!
    defaults.set("sparkles", forKey: MenuBarStore.styleKey)
    #expect(MenuBarStore(defaults: defaults).style == .countAndBar)
}
