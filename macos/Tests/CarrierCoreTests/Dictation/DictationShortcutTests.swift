import Foundation
import Testing
@testable import CarrierCore

private func record(_ keyCode: Int, _ characters: String, _ modifiers: ShortcutModifiers) -> ShortcutRecording {
    recordShortcut(keyCode: keyCode, characters: characters, modifiers: modifiers, bundle: english.bundle, locale: english.locale)
}

@Test func theDefaultShortcutIsOptionShiftSpace() {
    #expect(DictationShortcut.standard.text == "⌥⇧ Space" && DictationShortcut.standard.keyCode == 49)
}

@Test(arguments: [
    (0, "a", ShortcutModifiers([])), (49, " ", []), (0, "a", [.shift]), (122, "", []),
] as [(Int, String, ShortcutModifiers)])
func aCombinationWithNoControlOptionOrCommandIsRefusedWithTheReason(keyCode: Int, characters: String, modifiers: ShortcutModifiers) {
    guard case .refused(let reason) = record(keyCode, characters, modifiers) else {
        Issue.record("accepted")
        return
    }
    #expect(reason.contains("⌃, ⌥ or ⌘"))
}

@Test func aCombinationWithAModifierIsAcceptedAndShownInTheOrderOfTheMenus() {
    #expect(record(49, " ", [.option]) == .accepted(DictationShortcut(stored: "4:49:Space")!))
    guard case .accepted(let shortcut) = record(2, "d", [.command, .shift, .control]) else {
        Issue.record("refused")
        return
    }
    #expect(shortcut.text == "⌃⇧⌘ D" && shortcut.keyCode == 2)
    guard case .accepted(let named) = record(122, "\u{F704}", [.option]) else {
        Issue.record("refused")
        return
    }
    #expect(named.text == "⌥ F1")
}

@Test func aKeyWithNoNameAndNoPrintableCharacterIsRefused() {
    #expect(record(200, "\u{F73B}", [.command]) == .refused("That key cannot be used"))
    #expect(record(200, "", [.command]) == .refused("That key cannot be used"))
    #expect(record(200, "ab", [.command]) == .refused("That key cannot be used"))
}

@Test func aShortcutIsKeptAsItIsAndAnythingElseReadsAsNothing() throws {
    for shortcut in [DictationShortcut.standard, try #require(DictationShortcut(stored: "9:2:D"))] {
        #expect(DictationShortcut(stored: shortcut.stored) == shortcut)
    }
    // no modifier, an unknown name for the key, a missing part, and text
    for stored in ["0:49:Space", "2:49:Space", "4:49:Spacebar", "4:49", "", "x:y:z", "4:0:"] {
        #expect(DictationShortcut(stored: stored) == nil, "\(stored)")
    }
}

@Test func theLineOfTheWidgetSaysHowTheDictationEnds() {
    #expect(dictationHint(shortcut: .standard, activation: .toggle, bundle: english.bundle, locale: english.locale) == "⌥⇧ Space to finish · Esc to cancel")
    #expect(dictationHint(shortcut: .standard, activation: .hold, bundle: english.bundle, locale: english.locale) == "Release ⌥⇧ Space to finish · Esc to cancel")
}
