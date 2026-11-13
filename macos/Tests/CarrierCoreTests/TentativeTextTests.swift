import Foundation
import Testing
@testable import CarrierCore

/// A dictation that begins at `caret` in `text` and hears `events`: the text, the caret and the tentative range after the last.
private func hear(_ events: [DictationEvent], in text: String, caret: Int) -> (text: String, caret: Int, range: Range<Int>?) {
    var tentative = TentativeText(caret: caret, in: text)
    var now = (text: text, caret: caret)
    for event in events { if let edit = tentative.apply(event, to: now.text, caret: now.caret) { now = (edit.text, edit.caret) } }
    return (now.text, now.caret, tentative.range)
}

@Test(arguments: [
    // an empty box
    ([DictationEvent.partial("hola")], "", 0, "hola", 4, 0..<4 as Range<Int>?),
    ([.partial("hola"), .final("hola mundo")], "", 0, "hola mundo", 10, nil),
    // the caret at the start, in the middle and at the end of text that is left alone
    ([.partial("hola")], "uno dos", 0, "holauno dos", 4, 0..<4),
    ([.partial("hola ")], "uno dos", 4, "uno hola dos", 9, 4..<9),
    ([.partial("hola")], "uno dos", 7, "uno dos hola", 12, 8..<12),
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
    var tentative = TentativeText(caret: 4, in: "uno dos")
    _ = tentative.apply(.partial("hola"), to: "uno dos", caret: 4)
    tentative.close()
    #expect(tentative.range == nil)
    #expect(tentative.apply(.partial("x"), to: "uno holados", caret: 8)?.text == "uno hola xdos")
}

@Test func aCaretPastTheEndOfTheTextDoesNotCrash() {
    var tentative = TentativeText(caret: 9, in: "uno dos")
    #expect(tentative.apply(.final("ok"), to: "uno dos", caret: 7)?.text == "uno dos ok")
}

/// Dictating after a word, or twice in a row, sets the words apart; a dictation that starts a text, follows a space or a new line, or begins
/// with the mark that ends a phrase adds no space.
@Test(arguments: [
    ("Hola", 4, "necesito", "Hola necesito"),
    ("foo bar", 7, "baz", "foo bar baz"),
    ("uno dos", 3, "tres", "uno tres dos"),
    ("Hola ", 5, "necesito", "Hola necesito"),
    ("Hola\n", 5, "necesito", "Hola\nnecesito"),
    ("", 0, "necesito", "necesito"),
    ("Hola", 4, ", y", "Hola, y"),
    ("Hola", 4, " y", "Hola y"),
    ("Hola", 4, "", "Hola"),
])
func aDictationIsSetApartFromTheWordBeforeIt(text: String, caret: Int, heard: String, expected: String) {
    #expect(hear([.partial(heard), .final(heard)], in: text, caret: caret).text == expected)
}

@Test func theSpaceBeforeADictationIsWrittenOnceAndOutsideTheRange() {
    let heard = hear([.partial("hola"), .partial("hola mun")], in: "Hola", caret: 4)
    #expect(heard.text == "Hola hola mun" && heard.range == 5..<13 && heard.caret == 13)
}

/// The person edits while the dictation still has words to write (the last ones of a stop, or all of them for a model that answers at the end).
@Test func anEditBeforeTheRangeMovesItAndTheNextWordsGoWhereTheyWere() {
    var tentative = TentativeText(caret: 4, in: "uno dos")
    _ = tentative.apply(.partial("hola"), to: "uno dos", caret: 4)
    // "X" typed at the start, and the caret after it
    let edit = tentative.apply(.final("hola mundo"), to: "Xuno holados", caret: 1)
    #expect(edit?.text == "Xuno hola mundodos")
    // the caret stays where the person put it
    #expect(edit?.caret == 1 && tentative.range == nil)
}

@Test func aDeletionBeforeADictationThatHasWrittenNothingYetMovesItsPlace() {
    var tentative = TentativeText(caret: 4, in: "uno dos")
    #expect(tentative.apply(.final("hola "), to: "dos", caret: 0)?.text == "hola dos")
}

@Test func anEditAfterTheRangeLeavesItAlone() {
    var tentative = TentativeText(caret: 4, in: "uno dos")
    _ = tentative.apply(.partial("hola"), to: "uno dos", caret: 4)
    let edit = tentative.apply(.final("hola mundo"), to: "uno holados!", caret: 12)
    #expect(edit?.text == "uno hola mundodos!" && edit?.caret == 18)
}

@Test func anEditInsideTheRangeEndsTheWritingAndKeepsWhatThePersonDid() {
    var tentative = TentativeText(caret: 4, in: "uno dos")
    _ = tentative.apply(.partial("hola"), to: "uno dos", caret: 4)
    #expect(tentative.apply(.final("hola mundo"), to: "uno hoadados", caret: 7) == nil)
    #expect(tentative.range == nil && tentative.lost)
    // and nothing it hears later is written either
    #expect(tentative.apply(.partial("x"), to: "uno hoadados", caret: 7) == nil)
}

@Test func aTextReplacedWholeWhileTheDictationWaitsIsNotWrittenOver() {
    var tentative = TentativeText(caret: 4, in: "uno dos")
    #expect(tentative.apply(.final("hola"), to: "otro", caret: 4) == nil)
}
