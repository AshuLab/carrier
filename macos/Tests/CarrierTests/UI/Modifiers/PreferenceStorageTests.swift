import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private func scratch() -> UserDefaults { UserDefaults(suiteName: "storage-\(UUID().uuidString)")! }

@Test func aBoolPreferenceGivesItsDefaultAndThenWhatIsStored() {
    let defaults = scratch()
    #expect(AppStorage(Preference.menuAnimate, store: defaults).wrappedValue == true)
    defaults.set(false, forKey: Preference.menuAnimate.name)
    #expect(AppStorage(Preference.menuAnimate, store: defaults).wrappedValue == false)
}

@Test func anIntPreferenceGivesItsDefaultAndThenWhatIsStored() {
    let defaults = scratch()
    #expect(AppStorage(Preference.appearanceTextSize, store: defaults).wrappedValue == 100)
    defaults.set(115, forKey: Preference.appearanceTextSize.name)
    #expect(AppStorage(Preference.appearanceTextSize, store: defaults).wrappedValue == 115)
}

@Test func aDoublePreferenceGivesItsDefaultAndThenWhatIsStored() {
    let defaults = scratch()
    #expect(AppStorage(Preference.appearanceIconWeight, store: defaults).wrappedValue == 1.5)
    defaults.set(2.25, forKey: Preference.appearanceIconWeight.name)
    #expect(AppStorage(Preference.appearanceIconWeight, store: defaults).wrappedValue == 2.25)
}

@Test func aStringPreferenceGivesItsDefaultAndThenWhatIsStored() {
    let defaults = scratch()
    #expect(AppStorage(Preference.appearanceMonoFamily, store: defaults).wrappedValue == "System")
    defaults.set("Menlo", forKey: Preference.appearanceMonoFamily.name)
    #expect(AppStorage(Preference.appearanceMonoFamily, store: defaults).wrappedValue == "Menlo")
}

@Test func anEnumPreferenceGivesItsDefaultThenWhatIsStoredAndTheDefaultForAValueThatIsNotACase() {
    let defaults = scratch()
    #expect(AppStorage(Preference.appearanceDensity, store: defaults).wrappedValue == .comfortable)
    defaults.set("compact", forKey: Preference.appearanceDensity.name)
    #expect(AppStorage(Preference.appearanceDensity, store: defaults).wrappedValue == .compact)
    defaults.set("roomy", forKey: Preference.appearanceDensity.name)
    #expect(AppStorage(Preference.appearanceDensity, store: defaults).wrappedValue == .comfortable)
}

@Test func aWriteThroughTheStorageIsWhatTheTypedAccessorsRead() {
    let defaults = scratch()
    let density = AppStorage(Preference.appearanceDensity, store: defaults)
    density.wrappedValue = .compact
    #expect(AppPreferences(defaults: defaults).density == .compact)
    let accent = AppStorage(Preference.appearanceAccent, store: defaults)
    accent.wrappedValue = "blue"
    #expect(AppPreferences(defaults: defaults).accent == .blue)
}

@Test func anOptionalPreferenceIsNilWhileNoneIsSavedAndTakesTheSavedValueOutForNil() {
    let defaults = scratch()
    let translucent = AppStorage(Preference.appearanceTranslucent, store: defaults)
    let family = AppStorage(Preference.terminalFontFamily, store: defaults)
    let theme = AppStorage(Preference.terminalTheme, store: defaults)
    #expect(translucent.wrappedValue == nil && family.wrappedValue == nil && theme.wrappedValue == nil)
    translucent.wrappedValue = false
    family.wrappedValue = "Menlo"
    theme.wrappedValue = .ocean
    #expect(translucent.wrappedValue == false && family.wrappedValue == "Menlo" && theme.wrappedValue == .ocean)
    #expect(defaults.string(forKey: Preference.terminalTheme.name) == "ocean")
    translucent.wrappedValue = nil
    family.wrappedValue = nil
    theme.wrappedValue = nil
    #expect(defaults.object(forKey: Preference.appearanceTranslucent.name) == nil)
    #expect(defaults.object(forKey: Preference.terminalFontFamily.name) == nil)
    #expect(defaults.object(forKey: Preference.terminalTheme.name) == nil)
}

@Test func anOptionalEnumPreferenceReadsAStoredValueThatIsNotACaseAsNil() {
    let defaults = scratch()
    defaults.set("neon", forKey: Preference.terminalTheme.name)
    #expect(AppStorage(Preference.terminalTheme, store: defaults).wrappedValue == nil)
}
