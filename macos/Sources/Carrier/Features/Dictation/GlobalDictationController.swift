import AppKit
import CarrierCore

/// The global dictation of the app: the shortcut, the widget and the paste, around the machine of `CarrierCore/GlobalDictation.swift`. The shortcut is
/// registered only while Dictate in any app and the Dictation switch are both on (and not while the recorder of Settings listens for another), and Esc only
/// while the widget is open, so Carrier never holds a key it is not using.
@MainActor final class GlobalDictationController {
    static let shared = GlobalDictationController(dictation: .shared, shortcuts: SystemGlobalShortcut(), clipboard: SystemClipboard())

    private let dictation: DictationController
    private let preferences: AppPreferences
    private let shortcuts: any GlobalShortcut
    private let clipboard: any Clipboard
    private var machine: GlobalDictation!
    private var widget: DictationWidget!
    private var shortcut: AnyObject?
    private var escape: AnyObject?
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

    init(dictation: DictationController, preferences: AppPreferences = AppPreferences(), shortcuts: any GlobalShortcut, clipboard: any Clipboard) {
        self.dictation = dictation
        self.preferences = preferences
        self.shortcuts = shortcuts
        self.clipboard = clipboard
        machine = GlobalDictation(
            session: dictation.session, speechModel: { dictation.speechModel }, microphone: { dictation.microphoneStatus() },
            decision: FocusedField.decision, activation: { preferences.dictationActivation },
            moment: { [preferences] moment in dictationSound(for: moment, preferences.dictationSounds).map { DictationSoundPlayer.play($0) } },
            // the entry is of the take that just ended, whose audio goes with it
            record: { [dictation] in dictation.records.record($0, audio: dictation.session.take?.clip) }, frontApp: { NSWorkspace.shared.frontmostApplication?.localizedName },
            cleanup: { dictation.cleanup() }, cleanupModel: { preferences.dictationCleanupModel }, perform: { [unowned self] in perform($0) })
        widget = DictationWidget(dictation: machine, preferences: preferences, hint: { dictationHint(shortcut: preferences.dictationShortcut, activation: preferences.dictationActivation) },
            voice: { dictation.voice })
    }

    /// Follows the two switches, now and each time the preferences change.
    func start() {
        refresh()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private var isOn: Bool { globalDictationIsOn(dictation: preferences.dictationEnabled, global: preferences.dictationGlobal) && recording == false }

    private func refresh() {
        let wanted = isOn ? preferences.dictationShortcut : nil
        guard wanted != registered else { return }
        registered = wanted
        shortcut = nil
        if let wanted {
            shortcut = shortcuts.register(
                wanted, pressed: { [weak self] in MainActor.assumeIsolated { self?.shortcutPressed() } },
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
            // turned off, or handed to the recorder, while macOS asked
            guard heldUp == false, isOn else { return }
            machine.handle(.down)
        }
    }

    /// "Dictate now" of the status menu: the press of the shortcut, from a click. No release follows a click, so even in Hold the take ends with a
    /// second press, as in Toggle.
    func dictateFromMenu() { shortcutPressed() }

    private func shortcutReleased() {
        if asking {
            heldUp = preferences.dictationActivation == .hold
        } else if boxHeld {
            boxHeld = false
            dictation.endHold()
        } else {
            machine.handle(.up)
        }
    }

    func perform(_ effect: GlobalDictationEffect) {
        switch effect {
        case .show:
            widget.show()
            escape = shortcuts.register(.escape) { [weak self] in MainActor.assumeIsolated { self?.machine.handle(.escape) } }
        case .close:
            widget.close()
            escape = nil
        case .paste(let text): Task { await clipboard.paste(text) }
        case .copy(let text):
            // the widget is left open with buttons, which take clicks and the keyboard: the hot key of Esc is let go, so the panel's own Esc (and Dismiss, and the shortcut) closes it
            widget.takeClicks()
            escape = nil
            clipboard.copy(text)
        }
    }
}
