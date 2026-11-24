import Testing
@testable import CarrierCore

@Test func theStartSoundPlaysWhenItBeginsToListenAndTheEndSoundWhenThePersonStopsIt() {
    let sounds = DictationSounds()
    #expect(dictationSound(for: .listening, sounds) == SoundToPlay(name: "Tink", volume: 0.6))
    #expect(dictationSound(for: .stopped, sounds) == SoundToPlay(name: "Pop", volume: 0.6))
}

@Test func aCancelPlaysNoSoundAtAll() {
    #expect(dictationSound(for: .cancelled, DictationSounds()) == nil)
}

@Test func aSwitchOffSilencesItsOwnSoundOnly() {
    var sounds = DictationSounds()
    sounds.startOn = false
    #expect(dictationSound(for: .listening, sounds) == nil && dictationSound(for: .stopped, sounds) != nil)
    sounds.startOn = true
    sounds.endOn = false
    #expect(dictationSound(for: .listening, sounds) != nil && dictationSound(for: .stopped, sounds) == nil)
}

@Test func volumeZeroSilencesBothAndTheLoudestIsFull() {
    var sounds = DictationSounds()
    sounds.volume = 0
    #expect(dictationSound(for: .listening, sounds) == nil && dictationSound(for: .stopped, sounds) == nil)
    sounds.volume = 100
    #expect(dictationSound(for: .listening, sounds)?.volume == 1)
    sounds.volume = 400
    #expect(dictationSound(for: .listening, sounds)?.volume == 1)
}

@Test func theSoundsOnOfferAreMacOSsOwn() {
    #expect(dictationSoundChoices.allSatisfy { ["Tink", "Pop", "Glass"].contains($0) })
    #expect(dictationSoundChoices.contains(DictationSounds.defaultStart) && dictationSoundChoices.contains(DictationSounds.defaultEnd))
}
