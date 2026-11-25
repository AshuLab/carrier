import CarrierCore
import SwiftUI

/// The colors of what an agent is doing, which a session's ring, its clock and the chat's cards share.
extension Color {
    /// The violet of the agent's thinking, and of the ring that goes round a working session's icon.
    public static let thought = Color(Tokens.Status.thought)

    /// The green of "Done" (the turn ended and the person has not opened the session): a lighter one on dark, a deeper one on light.
    public static let sessionDone = Color(Tokens.Status.done)

    /// The cyan of a session whose turn ended while the agent waits for something it started: its ring and its clock, apart from the violet of one that works.
    public static let backgroundWork = Color(Tokens.Status.background)
}
