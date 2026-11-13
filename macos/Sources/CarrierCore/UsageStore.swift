import Foundation
import Observation

/// The Usage page's state: the last `usage` answer, the filters it was asked with and which providers are unfolded. Asked of a host that lists
/// `usage`; an older one is told apart from one that does not answer, so the page can say what to do.
@MainActor @Observable public final class UsageStore {
    public private(set) var snapshot: UsageSnapshot?
    /// The live quotas of every provider: the list on the page does not shrink to the provider the person filtered the consumption by.
    public private(set) var quotas: [UsageQuota] = []
    /// The first answer is on its way: there is nothing to show yet.
    public private(set) var isLoading = false
    /// An answer is on its way and the last one stays on the page.
    public private(set) var isRefreshing = false
    /// Why the last ask did not answer, in words; nil when it did. The last snapshot, if any, stays.
    public private(set) var error: String?

    // The filters are the person's; changing one is followed by `load`. The metric only changes what the page draws.
    public var metric = UsageMetric.cost
    public var days = 30
    public var providerFilter = UsageProviderFilter.all
    public var sourceFilter = UsageSourceFilter.all
    public var searchText = ""
    /// The providers whose accounts are shown under their row.
    public var expandedProviders: Set<String> = []

    @ObservationIgnored private let host: ChatHost
    /// Counts the asks, so an answer to a filter that has since changed does not replace a newer one.
    @ObservationIgnored private var asked = 0

    public init(host: ChatHost) { self.host = host }

    /// A click on a provider's row: filters by it, or by all again when it already is the filter. The caller asks again with `load`.
    public func toggleFilter(_ provider: UsageProviderFilter) { providerFilter = providerFilter.toggled(provider) }

    public func toggleProvider(_ provider: String) {
        if expandedProviders.remove(provider) == nil { expandedProviders.insert(provider) }
    }

    /// Asks the host with the filters as they are; `refresh` skips the quotas it kept for a minute.
    public func load(refresh: Bool = false) async {
        asked += 1
        let mine = asked
        if snapshot == nil { isLoading = true } else { isRefreshing = true }
        defer { if mine == asked { isLoading = false; isRefreshing = false } }
        var query = UsageQuery(refresh: refresh, days: days, provider: providerFilter, source: sourceFilter, search: searchText)
        do {
            guard try await host.capabilities().contains(.usage) else {
                if mine == asked { error = usageNeedsNewerHost }
                return
            }
            // the host filters the quotas by provider too: with a filter on, the quotas of all are asked apart (the refresh goes with them)
            var all: [UsageQuota]?
            if providerFilter != .all {
                all = try await host.usage(UsageQuery(refresh: refresh, days: 7)).quotas
                query.refresh = false
            }
            let reply = try await host.usage(query)
            if mine == asked {
                snapshot = reply
                quotas = all ?? reply.quotas
                error = nil
            }
        } catch {
            if mine == asked { self.error = ConversationModel.words(error) }
        }
    }

    /// Prices a model by the person's rule and asks again, so the cost on the page follows. Returns why it did not, in words; nil when it did.
    public func override(_ override: UsageOverride) async -> String? {
        do {
            guard try await host.capabilities().contains(.usageOverride) else { return usageNeedsNewerHost }
            try await host.usageOverride(override)
        } catch {
            return ConversationModel.words(error)
        }
        await load()
        return nil
    }
}
