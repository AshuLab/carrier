import Foundation
import Testing
@testable import CarrierCore

/// A dictation that begins at `caret` in `text` and hears `events`: the text, the caret and the tentative range after the last.
private func hear(_ events: [DictationEvent], in text: String, caret: Int) -> (text: String, caret: Int, range: Range<Int>?) {
    var tentative = TentativeText(caret: caret)
    var now = (text: text, caret: caret)
    for event in events { if let edit = tentative.apply(event, to: now.text) { now = (edit.text, edit.caret) } }
    return (now.text, now.caret, tentative.range)
}

@Test(arguments: [
    // an empty box
    ([DictationEvent.partial("hola")], "", 0, "hola", 4, 0..<4 as Range<Int>?),
    ([.partial("hola"), .final("hola mundo")], "", 0, "hola mundo", 10, nil),
    // the caret at the start, in the middle and at the end of text that is left alone
    ([.partial("hola")], "uno dos", 0, "holauno dos", 4, 0..<4),
    ([.partial("hola ")], "uno dos", 4, "uno hola dos", 9, 4..<9),
    ([.partial("hola")], "uno dos", 7, "uno doshola", 11, 7..<11),
    ([.final("hola ")], "uno dos", 4, "uno hola dos", 9, nil),
    // a partial replaced by a longer one, and by a shorter one
    ([.partial("hola"), .partial("hola mun")], "uno dos", 4, "uno hola mundos", 12, 4..<12),
    ([.partial("hola mun"), .partial("hola")], "uno dos", 4, "uno holados", 8, 4..<8),
    // a final closes the range at the caret, and the next words open another after it
    ([.partial("hola"), .final("hola."), .partial(" y")], "uno dos", 4, "uno hola. ydos", 11, 9..<11),
    // an empty final removes the partial, and one with nothing to remove writes nothing
    ([.partial("ruido"), .final("")], "uno dos", 4, "uno dos", 4, nil),
    ([.final("")], "", 0, "", 0, nil),
    ([.final("")], "uno dos", 7, "uno dos", 7, nil),
    // a failure writes nothing
    ([.partial("hola"), .failed(DictationFailure("no"))], "", 0, "hola", 4, 0..<4),
])
func theTentativeTextOnlyTouchesItsRange(events: [DictationEvent], text: String, caret: Int, expected: String, expectedCaret: Int, expectedRange: Range<Int>?) {
    let heard = hear(events, in: text, caret: caret)
    #expect(heard.text == expected)
    #expect(heard.caret == expectedCaret)
    #expect(heard.range == expectedRange)
}

@Test func closingKeepsThePartialTextAsFinalAndTheNextWordsFollowIt() {
    var tentative = TentativeText(caret: 4)
    _ = tentative.apply(.partial("hola"), to: "uno dos")
    tentative.close()
    #expect(tentative.range == nil)
    #expect(tentative.apply(.partial("x"), to: "uno holados")?.text == "uno holaxdos")
}

@Test func aTextShorterThanTheRangeDoesNotCrash() {
    var tentative = TentativeText(caret: 4)
    _ = tentative.apply(.partial("hola"), to: "uno dos")
    #expect(tentative.apply(.final("ok"), to: "un")?.text == "unok")
}
