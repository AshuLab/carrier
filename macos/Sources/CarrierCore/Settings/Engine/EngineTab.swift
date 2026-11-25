import Foundation

// The readiness banner of Settings (docs/specs/macos-app-redesign.md, story 30) as plain values. `node` and the `PATH` come from the shell, and
// `carrier` from Homebrew or the one the person chose under Programs on the Engine page.

public struct ReadinessBanner: Equatable {
    public enum State: Equatable { case ready, missing, detecting }

    public var state: State
    public var title: String
    public var detail: String
}

/// `missing` is what `startMissing` says.
public func readinessBanner(missing: [String], detecting: Bool, bundle: Bundle? = nil, locale: Locale = .current) -> ReadinessBanner {
    if detecting {
        return ReadinessBanner(
            state: .detecting, title: Copy.engineReadinessLooking(bundle: bundle, locale: locale), detail: Copy.engineReadinessLookingDetail(bundle: bundle, locale: locale))
    }
    if missing.isEmpty {
        return ReadinessBanner(
            state: .ready, title: Copy.engineReadinessReady(bundle: bundle, locale: locale), detail: Copy.engineReadinessReadyDetail(bundle: bundle, locale: locale))
    }
    let names = missing.count == 2 ? Copy.engineNamesAnd(first: missing[0], second: missing[1], bundle: bundle, locale: locale) : missing.joined(separator: ", ")
    return ReadinessBanner(
        state: .missing, title: Copy.engineReadinessNeeds(names: names, bundle: bundle, locale: locale),
        detail: Copy.engineReadinessMissingDetail(bundle: bundle, locale: locale)
    )
}
