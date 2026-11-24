import CarrierCore
import Testing

@Test(arguments: [(true, false, true), (true, true, false), (false, false, false), (false, true, false)])
func theRingTurnsOnlyWhileVisibleAndWithoutReduceMotion(visible: Bool, reduceMotion: Bool, turns: Bool) {
    #expect(ringAnimates(windowVisible: visible, reduceMotion: reduceMotion) == turns)
}
