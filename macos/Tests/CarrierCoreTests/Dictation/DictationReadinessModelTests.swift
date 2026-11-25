import Testing
@testable import CarrierCore

private func readiness(
    enabled: Bool = true, microphone: MicrophonePermission = .allowed, trusted: Bool = true, global: Bool = true, model: DictationModelReadiness = .ready("Apple")
) -> DictationReadiness {
    dictationReadiness(enabled: enabled, microphone: microphone, accessibilityTrusted: trusted, globalOn: global, model: model,
        bundle: english.bundle, locale: english.locale
    )
}

@Test func everythingInPlaceIsReadyToDictateAndSaysNothingIsWrong() {
    let now = readiness()
    #expect(now.tone == .ready && now.title == "Ready to dictate" && now.notes.isEmpty)
    #expect(now.items.map(\.title) == ["Microphone", "Accessibility", "Apple"] && now.items.allSatisfy { $0.mark == .ok && $0.fix == nil })
}

@Test func withDictationOffNothingIsCheckedAndTheCardSaysItIsOff() {
    let off = readiness(enabled: false, microphone: .denied, trusted: false)
    #expect(off.tone == .off && off.title == "Dictation is off" && off.items.isEmpty && off.notes.count == 1)
}

@Test func aBlockedMicrophoneIsWhatStopsDictationAndOffersItsFix() {
    let blocked = readiness(microphone: .denied, trusted: false)
    #expect(blocked.tone == .blocked && blocked.title == "Cannot listen yet")
    #expect(blocked.notes.first?.contains("blocked") == true)
    #expect(blocked.items.first?.fix == .openMicrophoneSettings && blocked.items.first?.state == "Not allowed")
}

@Test func accessibilityOnlyMattersWhileDictatingInAnyAppIsOn() {
    let missing = readiness(trusted: false)
    #expect(missing.tone == .attention && missing.title == "Ready, with one thing to fix")
    #expect(missing.items[1].mark == .attention && missing.items[1].fix == .openAccessibilitySettings)
    #expect(missing.notes == ["Without Accessibility the text goes on the clipboard instead of being pasted."])
    // with the shortcut off nothing is pasted into another app: the permission is shown, not asked for
    let notNeeded = readiness(trusted: false, global: false)
    #expect(notNeeded.tone == .ready && notNeeded.items[1].mark == .off && notNeeded.items[1].fix == nil && notNeeded.items[1].state == "Not allowed")
}

@Test func aModelNotOnDiskOrStillDownloadingIsToldAndCountsOnlyWhenItIsMissing() {
    let missing = readiness(model: .missing("Whisper Small"))
    #expect(missing.tone == .attention && missing.items[2].state == "not on disk" && missing.notes.first?.hasPrefix("Whisper Small is not on disk") == true)
    let downloading = readiness(model: .downloading("Parakeet Ultra"))
    #expect(downloading.tone == .ready && downloading.items[2].state == "downloading" && downloading.items[2].mark == .off)
}

@Test func twoThingsToFixAreCountedAndAnUnaskedMicrophoneIsOnlyANote() {
    let two = readiness(trusted: false, model: .missing("Whisper Small"))
    #expect(two.title == "Ready, with 2 things to fix" && two.notes.count == 2)
    let unasked = readiness(microphone: .notAsked)
    #expect(unasked.tone == .ready && unasked.items[0].mark == .off && unasked.notes == ["Carrier asks macOS the first time you dictate."])
}

@Test func theScreensOfThePageHaveATitleAndALineAndTheirPathIsTheirName() {
    #expect(DictationScreen.allCases.map(\.rawValue) == ["recognition", "global", "cleanup", "sounds", "history", "statistics"])
    #expect(DictationScreen.allCases.allSatisfy { $0.title(bundle: english.bundle, locale: english.locale).isEmpty == false && $0.detail(bundle: english.bundle, locale: english.locale).isEmpty == false })
    #expect(DictationScreen.statistics.title(bundle: english.bundle, locale: english.locale) == "Statistics"
            && DictationScreen.recognition.title(bundle: english.bundle, locale: english.locale) == "Speech recognition")
}
