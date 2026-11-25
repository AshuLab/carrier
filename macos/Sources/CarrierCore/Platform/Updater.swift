import Foundation

/// What the app needs of its updater: what the sidebar's pill draws and does, and what Settings > About shows and changes. The app's is Sparkle
/// (`Carrier/Platform/AppUpdater.swift`); the views take this, so a fake can stand for it.
@MainActor public protocol Updater: AnyObject {
    /// False for a build with no updater (a fixture, `swift run`): the page says so and changes nothing.
    var isRunning: Bool { get }
    /// The update on its way, which the pill draws; `press` is the pill's click.
    var flow: UpdateFlow { get }
    func press()
    var checksAutomatically: Bool { get set }
    var installsAutomatically: Bool { get set }
    /// False while a check or an update found waits for the person.
    var canCheck: Bool { get }
    var lastCheck: Date? { get }
    func checkNow()
}
