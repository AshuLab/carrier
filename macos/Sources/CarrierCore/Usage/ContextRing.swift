import Foundation

extension AccountUsage {
    /// The window the ring's inner circle follows: the 5h, else Weekly, else Monthly (Codex's free plan has only that one).
    public var ringWindow: (kind: QuotaKind, shape: MeterShape)? {
        if let five { return (.fiveHour, five) }
        if let weekly { return (.weekly, weekly) }
        return monthly.map { (.monthly, $0) }
    }
}

/// The ring in words, for its tooltip and for VoiceOver: what each circle says, and what the color and the dimming say that a screen reader cannot see
/// (orange from 90 % is "near the limit"; a check that was refused leaves the numbers "last known").
public func contextRingWords(context: ContextUse?, usage: AccountUsage?, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    func part(_ name: String, _ share: Double) -> String {
        let percent = Int((share * 100).rounded())
        return share >= 0.9
            ? Copy.usageRingPartNear(name: name, percent: percent, bundle: bundle, locale: locale) : Copy.usageRingPart(name: name, percent: percent, bundle: bundle, locale: locale)
    }
    let window = usage?.ringWindow
    let context: String? = context?.share.map { part(Copy.usageContext(bundle: bundle, locale: locale), $0) }
    let limit: String? = window.map { part($0.kind.title(bundle: bundle, locale: locale), $0.shape.used) }
    var parts = [context, limit].compactMap { $0 }
    guard parts.isEmpty == false else { return Copy.usageRingNone(bundle: bundle, locale: locale) }
    if window != nil, usage?.stale == true { parts.append(Copy.usageRingStale(bundle: bundle, locale: locale)) }
    return parts.joined(separator: " · ")
}

/// Why the popover of the ring has no meters: the account is signed out, the check failed or is still on its way, or the account has no limits to tell
/// (a local server). An ask that failed (a host too old for `usage`, one that did not answer) is not "still checking": Usage says why.
public func contextLimitsWords(
    account: String, quotas: [UsageQuota], failed: Bool, checking: Bool, bundle: Bundle? = nil, locale: Locale = .current
) -> String {
    if let quota = quotas.first(where: { $0.account == account }) {
        return quota.status == .signedOut
            ? Copy.usageLimitsSignedOut(name: quota.displayName ?? account, bundle: bundle, locale: locale) : Copy.usageLimitsNone(bundle: bundle, locale: locale)
    }
    if failed { return Copy.usageLimitsFailed(bundle: bundle, locale: locale) }
    return checking ? Copy.usageLimitsChecking(bundle: bundle, locale: locale) : Copy.usageLimitsNone(bundle: bundle, locale: locale)
}
