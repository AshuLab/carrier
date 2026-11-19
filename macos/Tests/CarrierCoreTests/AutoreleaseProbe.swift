import Foundation

/// How many `Freeable`s were freed: one per test, so tests running side by side do not count each other's.
final class FreedBox: @unchecked Sendable {
    var freed = 0
}

/// An object that counts its own freeing, to tell whether a pass of a long-lived thread's loop frees what it autoreleased
/// (inside an `autoreleasepool`) or leaves it for when the thread ends.
final class Freeable: NSObject {
    private let box: FreedBox
    private init(_ box: FreedBox) { self.box = box }
    deinit { box.freed += 1 }

    /// Makes one and leaves it to the innermost autorelease pool.
    static func autoreleaseOne(into box: FreedBox) { _ = Unmanaged.passRetained(Freeable(box)).autorelease() }
}
