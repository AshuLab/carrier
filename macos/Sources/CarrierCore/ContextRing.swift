import Foundation

extension AccountUsage {
    /// The window the ring's inner circle follows: the 5h, else Weekly, else Monthly (Codex's free plan has only that one).
    public var ringWindow: (name: String, shape: MeterShape)? {
        if let five { return ("5h", five) }
        if let weekly { return ("Weekly", weekly) }
        return monthly.map { ("Monthly", $0) }
    }
}

/// The ring in words, for its tooltip and for VoiceOver: what each circle says, and what the color and the dimming say that a screen reader cannot see
/// (orange from 90 % is "near the limit"; a check that was refused leaves the numbers "last known").
public func contextRingWords(context: ContextUse?, usage: AccountUsage?) -> String {
    func part(_ name: String, _ share: Double) -> String {
        let percent = "\(Int((share * 100).rounded()))%"
        return share >= 0.9 ? "\(name) \(percent), near the limit" : "\(name) \(percent)"
    }
    let window = usage?.ringWindow
    var parts = [context?.share.map { part("Context", $0) }, window.map { part($0.name, $0.shape.used) }].compactMap { $0 }
    guard parts.isEmpty == false else { return "Context and usage limits" }
    if window != nil, usage?.stale == true { parts.append("limits last known") }
    return parts.joined(separator: " · ")
}
