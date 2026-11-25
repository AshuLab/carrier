import Foundation

// What VoiceOver says for the rows of the log, built here so it is tested (spec section 4, "Accessibility").

/// A duration in words: "725 milliseconds", "2 seconds", "5.2 seconds", "2 minutes 5 seconds", "1 hour 3 minutes"; in the language of `locale`.
public func spokenDuration(_ ms: Int, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    if ms < 1000 { return Copy.logSpokenMilliseconds(count: max(0, ms), bundle: bundle, locale: locale) }
    let tenths = (ms + 50) / 100
    if tenths < 600 {
        if tenths % 10 == 0 { return Copy.logSpokenSeconds(count: tenths / 10, bundle: bundle, locale: locale) }
        let seconds = (Double(tenths) / 10).formatted(.number.precision(.fractionLength(1)).locale(locale))
        return Copy.logSpokenSecondsTenths(seconds: seconds, bundle: bundle, locale: locale)
    }
    let seconds = max(ms, 60_000) / 1000
    let (hours, minutes) = (seconds / 3600, seconds % 3600 / 60)
    var parts: [String] = []
    if hours > 0 { parts.append(Copy.logSpokenHours(count: hours, bundle: bundle, locale: locale)) }
    if minutes > 0 { parts.append(Copy.logSpokenMinutes(count: minutes, bundle: bundle, locale: locale)) }
    if hours == 0 && seconds % 60 > 0 { parts.append(Copy.logSpokenSeconds(count: seconds % 60, bundle: bundle, locale: locale)) }
    return parts.joined(separator: " ")
}

/// A call that is a row of its own (a skill): its name, how it ended and how long it took, whether or not the duration is drawn.
/// "solve:ship, succeeded, 725 milliseconds"; a running call has no duration yet.
public func callAccessibilityLabel(_ call: ToolCall, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    var parts = [call.arg]
    switch call.status {
    case .failed: parts.append(Copy.logCallStatus(status: .failed, bundle: bundle, locale: locale))
    case .running: parts.append(Copy.logCallStatus(status: .running, bundle: bundle, locale: locale))
    case .stopped: parts.append(Copy.logCallStatus(status: .stopped, bundle: bundle, locale: locale))
    case .ok: parts.append(Copy.logCallStatus(status: .ok, bundle: bundle, locale: locale))
    }
    if call.status != .running, let ms = call.durationMs { parts.append(spokenDuration(ms, bundle: bundle, locale: locale)) }
    return parts.joined(separator: ", ")
}

/// The closing row of a session: "Completed, CI passed, closed"; "Needs a human" says nothing of open or closed, there is nothing behind it.
/// The outcome is the card's own words, said in its language already.
public func resultAccessibilityLabel(_ card: ResultCard, open: Bool, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    let verdict = card.ci.map { ci -> String in
        switch ci.verdict {
        case "passed": Copy.logCiPassed(bundle: bundle, locale: locale)
        case "absent": Copy.logCiAbsent(bundle: bundle, locale: locale)
        default: Copy.logCiOther(verdict: ci.verdict, bundle: bundle, locale: locale)
        }
    }
    let state = open ? Copy.logResultOpen(bundle: bundle, locale: locale) : Copy.logResultClosed(bundle: bundle, locale: locale)
    return [card.outcome, verdict, card.hasDetails ? state : nil].compactMap { $0 }.joined(separator: ", ")
}
