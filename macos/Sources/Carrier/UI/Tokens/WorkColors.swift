import AppKit
import SwiftUI

/// The colors of what an agent is doing, which a session's ring, its clock and the chat's cards share.
extension Color {
    /// The violet of the agent's thinking, and of the ring that goes round a working session's icon.
    static let thought = Color(red: 0.79, green: 0.63, blue: 1.0)

    /// The green of "Done" (the turn ended and the person has not opened the session): a lighter one on dark, a deeper one on light.
    static let sessionDone = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.19, green: 0.70, blue: 0.31, alpha: 1) : NSColor(red: 0.12, green: 0.55, blue: 0.24, alpha: 1)
    })

    /// The cyan of a session whose turn ended while the agent waits for something it started: its ring and its clock, apart from the violet of one that works.
    static let backgroundWork = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.35, green: 0.78, blue: 0.98, alpha: 1) : NSColor(red: 0.0, green: 0.48, blue: 0.70, alpha: 1)
    })
}
