import Foundation

/// Hands a one-use script to the user's terminal; the app's is `NSWorkspace`, tests record the call.
public protocol TerminalOpener {
    func open(_ script: URL) throws
}
