import Carbon.HIToolbox
import CarrierCore
import Foundation

/// A system hot key (Carbon `RegisterEventHotKey`), which needs no permission: `pressed` runs on the main thread each time the combination goes down,
/// and `released` each time the key comes up (a hold ends there).
/// It stops being registered when the object goes. The status of the registration says nothing of a collision: another app may hold the same
/// combination, and the system tells neither, which is why the default is one no installed app was found to use (docs/research/global-dictation-input.md).
final class GlobalHotKey {
    struct Shortcut: Equatable {
        let keyCode: Int
        /// Carbon's modifiers (`optionKey`, `shiftKey`, ...).
        let modifiers: Int
        let text: String

        static let escape = Shortcut(keyCode: kVK_Escape, modifiers: 0, text: "Esc")
    }

    private static var lastID: UInt32 = 0
    private let id: UInt32
    private let pressed: () -> Void
    private let released: () -> Void
    private var key: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// nil when the system refuses it (the same combination already registered by this app, say), with the status on stderr.
    init?(_ shortcut: Shortcut, pressed: @escaping () -> Void, released: @escaping () -> Void = {}) {
        Self.lastID += 1
        id = Self.lastID
        self.pressed = pressed
        self.released = released
        var kinds = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var which = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &which)
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                guard which.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) { hotKey.released() } else { hotKey.pressed() }
                return noErr
            }, kinds.count, &kinds, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let registered = RegisterEventHotKey(
            UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), EventHotKeyID(signature: OSType(0x4352_4448), id: id), GetApplicationEventTarget(), 0, &key)
        guard installed == noErr, registered == noErr else {
            FileHandle.standardError.write(Data("carrier: the shortcut \(shortcut.text) could not be registered (\(installed), \(registered))\n".utf8))
            unregister()
            return nil
        }
    }

    deinit { unregister() }

    private func unregister() {
        if let key { UnregisterEventHotKey(key) }
        if let handler { RemoveEventHandler(handler) }
        key = nil
        handler = nil
    }
}

extension GlobalHotKey.Shortcut {
    /// What the person recorded, in Carbon's modifiers.
    init(_ shortcut: DictationShortcut) {
        let carbon = [(ShortcutModifiers.command, cmdKey), (.shift, shiftKey), (.option, optionKey), (.control, controlKey)]
        self.init(keyCode: shortcut.keyCode, modifiers: carbon.filter { shortcut.modifiers.contains($0.0) }.reduce(0) { $0 | $1.1 }, text: shortcut.text)
    }
}
