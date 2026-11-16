import AppKit
import CarrierCore

/// The global dictation of the app: the shortcut, the widget and the paste, around the machine of `CarrierCore/GlobalDictation.swift`. The shortcut is
/// registered only while Dictate in any app and the Dictation switch are both on (and not while the recorder of Settings listens for another), and Esc only
/// while the widget is open, so Carrier never holds a key it is not using.
@MainActor final class GlobalDictationController {
    static let shared = GlobalDictationController(dictation: .shared)

    private let dictation: DictationController
    private let preferences: AppPreferences
    private let board: NSPasteboard
    private var machine: GlobalDictation!
    private var widget: DictationWidget!
    private var shortcut: GlobalHotKey?
    private var escape: GlobalHotKey?
    /// The combination `shortcut` holds, so a new one replaces it at once.
    private var registered: DictationShortcut?
    /// The recorder of Settings is waiting for keys: the shortcut is let go so that pressing it records it instead of dictating.
    var recording = false { didSet { refresh() } }
    /// The key of a hold went up while the microphone was being asked for, so the dictation does not start with no key down.
    private var heldUp = false
    /// The press that went to a session's message box in a hold, which the release ends there as well.
    private var boxHeld = false
    /// The first dictation waits for macOS to answer the microphone's question; a press meanwhile is the same one.
    private var asking = false

    /// `board` is the one a paste goes through, the general pasteboard of a real build.
    init(dictation: DictationController, preferences: AppPreferences = AppPreferences(), board: NSPasteboard = .general) {
        self.dictation = dictation
        self.preferences = preferences
        self.board = board
        machine = GlobalDictation(
            session: dictation.session, speechModel: { dictation.speechModel }, microphone: { dictation.microphoneStatus() },
            decision: FocusedField.decision, activation: { preferences.dictationActivation },
            moment: { [preferences] moment in dictationSound(for: moment, preferences.dictationSounds).map { DictationSoundPlayer.play($0) } },
            perform: { [unowned self] in perform($0) })
        widget = DictationWidget(dictation: machine, hint: { dictationHint(shortcut: preferences.dictationShortcut, activation: preferences.dictationActivation) })
    }

    /// Follows the two switches, now and each time the preferences change.
    func start() {
        refresh()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        let on = globalDictationIsOn(dictation: preferences.dictationEnabled, global: preferences.dictationGlobal) && recording == false
        let wanted = on ? preferences.dictationShortcut : nil
        guard wanted != registered else { return }
        registered = wanted
        shortcut = nil
        if let wanted {
            shortcut = GlobalHotKey(
                .init(wanted), pressed: { [weak self] in MainActor.assumeIsolated { self?.shortcutPressed() } },
                released: { [weak self] in MainActor.assumeIsolated { self?.shortcutReleased() } })
        } else {
            // a dictation under way when it is turned off is cancelled, as Esc does
            machine.handle(.escape)
        }
    }

    private func shortcutPressed() {
        guard asking == false else { return }
        heldUp = false
        boxHeld = false
        // a session in front dictates in its own message box, and the shortcut again ends it (or the release does, in a hold); the widget in use is ended wherever the person is
        if machine.state == .idle, dictationRoute(for: WindowController.shared.dictationFront) == .messageBox {
            boxHeld = preferences.dictationActivation == .hold
            return WindowController.shared.dictateInMessageBox()
        }
        guard machine.state == .idle, dictation.microphoneStatus() == .notAsked else { return machine.handle(.down) }
        asking = true
        Task {
            await dictation.requestMicrophone()
            asking = false
            guard heldUp == false else { return }
            machine.handle(.down)
        }
    }

    private func shortcutReleased() {
        if asking {
            heldUp = preferences.dictationActivation == .hold
        } else if boxHeld {
            boxHeld = false
            if dictation.session.state != .idle { WindowController.shared.dictateInMessageBox() }
        } else {
            machine.handle(.up)
        }
    }

    private func perform(_ effect: GlobalDictationEffect) {
        switch effect {
        case .show:
            widget.show()
            escape = GlobalHotKey(.escape) { [weak self] in MainActor.assumeIsolated { self?.machine.handle(.escape) } }
        case .close:
            widget.close()
            escape = nil
        case .paste(let text): Task { await ClipboardPaste(board: board).paste(text) }
        case .copy(let text):
            // the widget is left open with buttons, which take clicks, and Esc goes back to the app: Dismiss and the shortcut close it
            widget.takeClicks()
            escape = nil
            board.clearContents()
            board.setString(text, forType: .string)
        }
    }
}
