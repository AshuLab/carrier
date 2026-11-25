import Foundation

/// The two things a keep awake may hold: the system's idle sleep, and the display's.
public enum AwakeAssertionKind: Sendable { case system, display }

/// What keeps the Mac awake, and the battery it reads for the rules; the app's is IOKit (`Carrier/Platform/SystemKeepAwakeAssertion.swift`),
/// the tests of `KeepAwakeController` take a fake.
@MainActor public protocol KeepAwakeAssertion: AnyObject {
    /// Whether the assertion of this kind is held now.
    func isHeld(_ kind: AwakeAssertionKind) -> Bool
    /// Takes it; false when the system refuses.
    func take(_ kind: AwakeAssertionKind) -> Bool
    func release(_ kind: AwakeAssertionKind)
    func powerFacts() -> PowerFacts
    /// `changed` runs on the main thread each time the battery's level or the source of power changes.
    func watchPower(_ changed: @escaping @MainActor () -> Void)
}
