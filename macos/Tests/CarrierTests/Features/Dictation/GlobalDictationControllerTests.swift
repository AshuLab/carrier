import CarrierCore
import Foundation
import Testing
@testable import Carrier

/// The shortcut and the clipboard the controller is given, written down.
@MainActor private final class Fakes: GlobalShortcut, Clipboard {
    final class Key {}
    struct Weak { weak var key: Key? }
    var registered: [DictationShortcut] = []
    private var keys: [Weak] = []
    var pasted: [String] = []
    var copied: [String] = []

    func register(_ shortcut: DictationShortcut, pressed: @escaping () -> Void, released: @escaping () -> Void) -> AnyObject? {
        let key = Key()
        registered.append(shortcut)
        keys.append(Weak(key: key))
        return key
    }

    func paste(_ text: String) async { pasted.append(text) }
    func copy(_ text: String) { copied.append(text) }

    /// The registrations the controller still holds.
    var live: Int { keys.filter { $0.key != nil }.count }
}

@MainActor private func controller(_ fakes: Fakes, global: Bool = true) -> (GlobalDictationController, AppPreferences) {
    let defaults = UserDefaults(suiteName: "global-dictation-controller-\(UUID().uuidString)")!
    let preferences = AppPreferences(defaults: defaults)
    preferences.dictationEnabled = true
    preferences.dictationGlobal = global
    let dictation = DictationController(registry: RecognizerRegistry(), preferences: preferences)
    return (GlobalDictationController(dictation: dictation, preferences: preferences, shortcuts: fakes, clipboard: fakes), preferences)
}

@MainActor @Test func theShortcutIsRegisteredOnlyWhileTheTwoSwitchesAreOnAndTheRecorderDoesNotListen() {
    let fakes = Fakes()
    let (global, preferences) = controller(fakes)
    global.start()
    #expect(fakes.registered == [preferences.dictationShortcut] && fakes.live == 1)
    // the recorder listens: the keys are let go, so pressing them records and does not dictate
    global.recording = true
    #expect(fakes.live == 0)
    global.recording = false
    #expect(fakes.registered.count == 2 && fakes.live == 1)
}

@MainActor @Test func withTheGlobalSwitchOffNoShortcutIsRegistered() {
    let fakes = Fakes()
    let (global, _) = controller(fakes, global: false)
    global.start()
    #expect(fakes.registered.isEmpty)
}

@MainActor @Test func aPasteAndACopyGoThroughTheClipboardTheControllerIsGiven() async {
    let fakes = Fakes()
    let (global, _) = controller(fakes)
    global.perform(.paste("dictated"))
    for _ in 0..<200 where fakes.pasted.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
    #expect(fakes.pasted == ["dictated"])
    global.perform(.copy("kept"))
    #expect(fakes.copied == ["kept"])
}
