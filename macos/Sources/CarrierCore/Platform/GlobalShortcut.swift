import Foundation

/// Keys that work in any app; the app's is a Carbon hot key, which needs no permission (`Carrier/Platform/GlobalHotKey.swift`), the tests take a fake.
@MainActor public protocol GlobalShortcut {
    /// `pressed` runs each time the combination goes down and `released` each time the key comes up (a hold ends there), both on the main thread.
    /// The keys stay registered for as long as the returned object lives; nil when the system refuses them (another app, or this one, holds them).
    func register(_ shortcut: DictationShortcut, pressed: @escaping () -> Void, released: @escaping () -> Void) -> AnyObject?
}

extension GlobalShortcut {
    public func register(_ shortcut: DictationShortcut, pressed: @escaping () -> Void) -> AnyObject? {
        register(shortcut, pressed: pressed, released: {})
    }
}
