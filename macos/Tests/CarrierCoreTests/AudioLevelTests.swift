import Foundation
import Testing
@testable import CarrierCore

@Test(arguments: [
    (Float(0), Float(0)),
    (-0.5, 0),
    (.nan, 0),
    (0.003, 0),  // about -50 dB: the floor
    (0.316, 1),  // -10 dB: the ceiling
    (0.0316, 0.5),  // -30 dB: halfway in decibels
    (4, 1),  // a clipped buffer
    (.infinity, 1),
])
func theLevelOfABufferGoesFromTheFloorToTheCeiling(rms: Float, level: Float) {
    #expect(abs(normalizedLevel(rms: rms) - level) < 0.02)
}

@Test func theLevelRisesFasterThanItFalls() {
    let up = smoothedLevel(from: 0, toward: 1)
    let down = 1 - smoothedLevel(from: 1, toward: 0)
    #expect(abs(up - 0.6) < 0.0001 && abs(down - 0.25) < 0.0001)
    #expect(up > down)
    // a voice that stops: the level lets go over several samples and never goes below zero
    var level: Float = 1
    for _ in 0..<3 { level = smoothedLevel(from: level, toward: 0) }
    #expect(level > 0.4 && level < 0.5)
}

@Test(arguments: [(Float(0), 0.4), (0.5, 0.7), (1, 1.0), (-1, 0.4), (3, 1.0)])
func theEdgeOpacityIs04Plus06TimesTheLevel(level: Float, opacity: Double) {
    #expect(abs(dictationEdgeOpacity(level: level) - opacity) < 0.0001)
}

@Test func theMeterPublishesAboutFifteenTimesASecondAndFollowsTheVoice() {
    var meter = LevelMeter()
    let rate = 16000.0
    let loud = AudioBuffer(samples: Array(repeating: 0.3, count: 1600), sampleRate: rate)  // 0.1 s
    var published = 0
    for _ in 0..<10 where meter.add(loud) != nil { published += 1 }  // one second of audio
    #expect(published == 10)
    #expect(meter.level > 0.9)
    // a buffer shorter than a fifteenth of a second waits for the next
    var short = LevelMeter()
    #expect(short.add(AudioBuffer(samples: Array(repeating: 0.3, count: 500), sampleRate: rate)) == nil)
    #expect(short.add(AudioBuffer(samples: Array(repeating: 0.3, count: 600), sampleRate: rate)) != nil)
    // silence after the voice lets the level go down gradually
    let before = meter.level
    _ = meter.add(AudioBuffer(samples: Array(repeating: 0, count: 1600), sampleRate: rate))
    #expect(meter.level < before && meter.level > before * 0.5)
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

@Test(arguments: [(Float(0), 0.21), (1, 0.6)])
func theLightTopsAt60PercentAndKeepsA35thOfThatInSilence(level: Float, opacity: Double) {
    #expect(abs(dictationLightOpacity(level: level) - opacity) < 0.0001)
}
