import Foundation
import Testing
@testable import CarrierCore

@Test(arguments: [
    (Float(0), Float(0)),
    (-0.5, 0),
    (.nan, 0),
    (0.0025, 0),  // about -52 dB: the floor
    (0.079, 1),  // -22 dB: the ceiling
    (0.0178, 0.567),  // -35 dB: just over halfway in decibels
    (4, 1),  // a clipped buffer
    (.infinity, 1),
])
func theLevelOfABufferGoesFromTheFloorToTheCeiling(rms: Float, level: Float) {
    #expect(abs(normalizedLevel(rms: rms) - level) < 0.02)
}

@Test func theFollowerGoesUpFasterThanItComesDown() {
    var follower = VoiceFollower()
    let loud = VoiceLevels(overall: 1, low: 1, mid: 1, high: 1)
    follower.step(toward: loud, seconds: 1.0 / 60)
    let up = follower.shown.overall
    follower.step(toward: .silence, seconds: 1.0 / 60)
    let down = up - follower.shown.overall
    #expect(up > 0.3 && down < up * 0.5)
    // a voice that stops: it lets go over a few tenths of a second, never below zero, and a frame of no time moves nothing
    for _ in 0..<60 { follower.step(toward: .silence, seconds: 1.0 / 60) }
    #expect(follower.shown.overall >= 0 && follower.shown.overall < 0.02)
    let held = follower.shown
    follower.step(toward: loud, seconds: 0)
    #expect(follower.shown == held)
}

@Test func theMeterPublishesAboutThirtyTimesASecondAsItHeardIt() {
    var meter = LevelMeter()
    let rate = 16000.0
    let loud = AudioBuffer(samples: Array(repeating: 0.3, count: 1600), sampleRate: rate)  // 0.1 s
    var published = 0
    for _ in 0..<10 where meter.add(loud) != nil { published += 1 }  // one second of audio
    #expect(published == 10)
    #expect(meter.level > 0.9)
    // a buffer shorter than a thirtieth of a second waits for the next
    var short = LevelMeter()
    #expect(short.add(AudioBuffer(samples: Array(repeating: 0.3, count: 300), sampleRate: rate)) == nil)
    #expect(short.add(AudioBuffer(samples: Array(repeating: 0.3, count: 300), sampleRate: rate)) != nil)
    // silence right after the voice reads as silence: the smoothing is the view's
    _ = meter.add(AudioBuffer(samples: Array(repeating: 0, count: 1600), sampleRate: rate))
    #expect(meter.level == 0)
}

@Test(arguments: [(150.0, 0), (800.0, 1), (5000.0, 2)])
func aToneLightsTheBandItBelongsTo(hertz: Double, band: Int) {
    var meter = LevelMeter()
    let rate = 16000.0
    let tone = (0..<3200).map { Float(0.02 * sin(2 * Double.pi * hertz * Double($0) / rate)) }  // 0.2 s
    var last = VoiceLevels.silence
    for chunk in stride(from: 0, to: tone.count, by: 800) {
        if let levels = meter.add(AudioBuffer(samples: Array(tone[chunk..<chunk + 800]), sampleRate: rate)) { last = levels }
    }
    let levels = [last.low, last.mid, last.high]
    #expect(levels.firstIndex(of: levels.max()!) == band)
}

private func degrees(_ color: HSB) -> Double { (color.hue * 360).rounded() }

@Test(arguments: [
    (HSB(hue: 175.0 / 360, saturation: 0.8, brightness: 0.7), [175.0, 215, 135]),  // teal
    (HSB(hue: 215.0 / 360, saturation: 0.9, brightness: 1), [215.0, 255, 175]),  // blue
    (HSB(hue: 0, saturation: 0.85, brightness: 0.9), [0.0, 40, 320]),  // red wraps below zero
])
func aColoredAccentGivesTwoNeighbouringHuesWithItsSaturationAndBrightness(accent: HSB, hues: [Double]) {
    let colors = dictationColors(accent: accent)
    #expect(colors.map(degrees) == hues)
    #expect(colors.allSatisfy { $0.saturation == accent.saturation && $0.brightness == accent.brightness })
}

@Test(arguments: [0.0, 0.1, 0.149])
func aGrayAccentKeepsItsHueAndOnlyTheBrightnessVaries(saturation: Double) {
    let accent = HSB(hue: 0.6, saturation: saturation, brightness: 0.5)
    let colors = dictationColors(accent: accent)
    #expect(colors.allSatisfy { $0.hue == accent.hue })
    #expect(Set(colors.map(\.brightness)).count == 3)
}

@Test func theEdgeIsDrawnOnlyWhileItListensAndWaitsForADrop() {
    for state in [DictationSession.State.idle, .gettingReady, .transcribing] {
        #expect(dictationEdgeShown(dictationPresentation(state, registered: true), dropping: false) == false)
    }
    #expect(dictationEdgeShown(nil, dropping: false) == false)
    #expect(dictationEdgeShown(dictationPresentation(.listening, registered: true), dropping: false))
    #expect(dictationEdgeShown(dictationPresentation(.listening, registered: true), dropping: true) == false)
}
