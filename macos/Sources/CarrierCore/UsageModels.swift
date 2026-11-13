import Foundation

// What the chat host's `usage` request answers (docs/specs/usage-and-limits.md, `src/usage/service.ts`): live quotas per account and what was
// used over the last days. Every decoder here is tolerant: a field the host leaves out is its default, and a value this app does not know is
// the closest quiet one, so a newer or older host never breaks the page.

/// The channels of a count of tokens; `input` leaves out the cached ones and `reasoning` is a part of `output`.
public struct UsageTokens: Decodable, Equatable {
    public let input, cachedInput, cacheWrite, output, reasoning: Int

    private enum CodingKeys: String, CodingKey { case input, cachedInput, cacheWrite, output, reasoning }

    public init(input: Int = 0, cachedInput: Int = 0, cacheWrite: Int = 0, output: Int = 0, reasoning: Int = 0) {
        self.input = input
        self.cachedInput = cachedInput
        self.cacheWrite = cacheWrite
        self.output = output
        self.reasoning = reasoning
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        input = try values.decodeIfPresent(Int.self, forKey: .input) ?? 0
        cachedInput = try values.decodeIfPresent(Int.self, forKey: .cachedInput) ?? 0
        cacheWrite = try values.decodeIfPresent(Int.self, forKey: .cacheWrite) ?? 0
        output = try values.decodeIfPresent(Int.self, forKey: .output) ?? 0
        reasoning = try values.decodeIfPresent(Int.self, forKey: .reasoning) ?? 0
    }
}

/// Tokens, cost and turns: the totals, and the part of a day, a model or a workspace that the rows below share.
public struct UsageRow: Decodable, Equatable {
    public let tokens: UsageTokens
    public let costUsd: Double
    public let turns: Int

    private enum CodingKeys: String, CodingKey { case tokens, costUsd, turns }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        tokens = try values.decodeIfPresent(UsageTokens.self, forKey: .tokens) ?? UsageTokens()
        costUsd = try values.decodeIfPresent(Double.self, forKey: .costUsd) ?? 0
        turns = try values.decodeIfPresent(Int.self, forKey: .turns) ?? 0
    }
}

public struct UsageDay: Decodable, Equatable {
    /// `YYYY-MM-DD`, in the host's local time.
    public let date: String
    public let row: UsageRow

    private enum CodingKeys: String, CodingKey { case date }

    public init(from decoder: Decoder) throws {
        date = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .date)
        row = try UsageRow(from: decoder)
    }
}

public struct UsageModel: Decodable, Equatable {
    public enum CostStatus: String { case priced, unpriced, local }

    public let model: String
    /// `claude`, `codex`, `agy` or `local`.
    public let provider: String
    public let isLocal: Bool
    /// `unpriced` is a model the price table does not know: its cost is not `$0.00`, it is missing.
    public let costStatus: CostStatus
    public let row: UsageRow

    private enum CodingKeys: String, CodingKey { case model, provider, isLocal, costStatus }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        model = try values.decode(String.self, forKey: .model)
        provider = try values.decodeIfPresent(String.self, forKey: .provider) ?? ""
        isLocal = try values.decodeIfPresent(Bool.self, forKey: .isLocal) ?? false
        costStatus = try values.decodeIfPresent(String.self, forKey: .costStatus).flatMap(CostStatus.init(rawValue:)) ?? .priced
        row = try UsageRow(from: decoder)
    }
}

public struct UsageWorkspace: Decodable, Equatable {
    public let workspace: String
    /// `epic`, `chat` or `external`.
    public let source: String
    public let row: UsageRow

    private enum CodingKeys: String, CodingKey { case workspace, source }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        workspace = try values.decodeIfPresent(String.self, forKey: .workspace) ?? ""
        source = try values.decodeIfPresent(String.self, forKey: .source) ?? ""
        row = try UsageRow(from: decoder)
    }
}

/// One rolling window of a quota: how much is used and when it resets, as a time or in the provider's own words.
public struct UsageWindow: Decodable, Equatable {
    public let id: String
    public let label: String
    /// The pool or limit the window belongs to, when the provider has several.
    public let group: String?
    public let usedPercent: Double
    /// Milliseconds since the epoch.
    public let resetsAt: Int?
    public let resetLabel: String?

    private enum CodingKeys: String, CodingKey { case id, label, group, usedPercent, resetsAt, resetLabel }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        label = try values.decodeIfPresent(String.self, forKey: .label) ?? id
        group = try values.decodeIfPresent(String.self, forKey: .group)
        usedPercent = try values.decodeIfPresent(Double.self, forKey: .usedPercent) ?? 0
        resetsAt = try values.decodeIfPresent(Int.self, forKey: .resetsAt)
        resetLabel = try values.decodeIfPresent(String.self, forKey: .resetLabel)
    }
}

/// Claude's overage spend, in dollars.
public struct UsageExtra: Decodable, Equatable {
    public let isEnabled: Bool
    public let monthlyLimitUsd: Double?
    public let usedCreditsUsd: Double?
    public let utilization: Double?
    public let currency: String?

    private enum CodingKeys: String, CodingKey { case isEnabled, monthlyLimitUsd, usedCreditsUsd, utilization, currency }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        monthlyLimitUsd = try values.decodeIfPresent(Double.self, forKey: .monthlyLimitUsd)
        usedCreditsUsd = try values.decodeIfPresent(Double.self, forKey: .usedCreditsUsd)
        utilization = try values.decodeIfPresent(Double.self, forKey: .utilization)
        currency = try values.decodeIfPresent(String.self, forKey: .currency)
    }
}

public struct UsageCredits: Decodable, Equatable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?

    private enum CodingKeys: String, CodingKey { case hasCredits, unlimited, balance }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = try values.decodeIfPresent(Bool.self, forKey: .hasCredits) ?? false
        unlimited = try values.decodeIfPresent(Bool.self, forKey: .unlimited) ?? false
        balance = try values.decodeIfPresent(String.self, forKey: .balance)
    }
}

/// A local server (LM Studio, Ollama) with the models it has loaded.
public struct UsageServer: Decodable, Equatable {
    public let kind: String
    public let running: Bool
    public let models: [String]

    private enum CodingKeys: String, CodingKey { case kind, running, models }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(String.self, forKey: .kind)
        running = try values.decodeIfPresent(Bool.self, forKey: .running) ?? false
        models = try values.decodeIfPresent([String].self, forKey: .models) ?? []
    }
}

/// The live quota of one account of `providers.json`, or of the local servers (account `local`).
public struct UsageQuota: Decodable, Equatable {
    public enum Status: String { case ok, signedOut = "signed_out", missing, unavailable, rateLimited = "rate_limited", error }

    public let account: String
    public let displayName: String?
    /// `claude`, `codex`, `agy` or `local`.
    public let provider: String
    public let status: Status
    /// Milliseconds since the epoch of the probe that produced the data.
    public let checkedAt: Int
    /// The windows are the last known ones: a later probe was rate limited.
    public let stale: Bool
    public let windows: [UsageWindow]
    public let planType: String?
    /// Why the status is not `ok`.
    public let message: String?
    public let extraUsage: UsageExtra?
    public let credits: UsageCredits?
    public let aiCreditsNotice: String?
    public let servers: [UsageServer]

    private enum CodingKeys: String, CodingKey {
        case account, displayName, provider, status, checkedAt, stale, windows, planType, message, extraUsage, credits, aiCreditsNotice, servers
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        account = try values.decode(String.self, forKey: .account)
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName)
        provider = try values.decode(String.self, forKey: .provider)
        // a status this app does not know is a quota it cannot show, not a failed page
        status = try values.decodeIfPresent(String.self, forKey: .status).flatMap(Status.init(rawValue:)) ?? .unavailable
        checkedAt = try values.decodeIfPresent(Int.self, forKey: .checkedAt) ?? 0
        stale = try values.decodeIfPresent(Bool.self, forKey: .stale) ?? false
        windows = try values.decodeIfPresent([UsageWindow].self, forKey: .windows) ?? []
        planType = try values.decodeIfPresent(String.self, forKey: .planType)
        message = try values.decodeIfPresent(String.self, forKey: .message)
        extraUsage = try values.decodeIfPresent(UsageExtra.self, forKey: .extraUsage)
        credits = try values.decodeIfPresent(UsageCredits.self, forKey: .credits)
        aiCreditsNotice = try values.decodeIfPresent(String.self, forKey: .aiCreditsNotice)
        servers = try values.decodeIfPresent([UsageServer].self, forKey: .servers) ?? []
    }
}

/// The reply of `usage`.
public struct UsageSnapshot: Decodable, Equatable {
    /// Milliseconds since the epoch.
    public let checkedAt: Int
    public let quotas: [UsageQuota]
    public let summary: UsageRow
    public let daily: [UsageDay]
    public let byModel: [UsageModel]
    public let byWorkspace: [UsageWorkspace]
    /// The models the price table knows, for an override to borrow the rates of one.
    public let catalogModels: [String]

    private enum CodingKeys: String, CodingKey { case checkedAt, quotas, summary, daily, byModel, byWorkspace, catalogModels }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        checkedAt = try values.decodeIfPresent(Int.self, forKey: .checkedAt) ?? 0
        quotas = try values.decodeIfPresent([UsageQuota].self, forKey: .quotas) ?? []
        summary = try values.decode(UsageRow.self, forKey: .summary)
        daily = try values.decodeIfPresent([UsageDay].self, forKey: .daily) ?? []
        byModel = try values.decodeIfPresent([UsageModel].self, forKey: .byModel) ?? []
        byWorkspace = try values.decodeIfPresent([UsageWorkspace].self, forKey: .byWorkspace) ?? []
        catalogModels = try values.decodeIfPresent([String].self, forKey: .catalogModels) ?? []
    }
}

/// What `usage` is asked: `days` is 7, 14, 30 or 90; `provider` and `source` filter the history (`provider` the quotas too), `search` is a
/// word of a model or workspace, `account` one account of `providers.json`. `refresh` skips the quotas the host kept for a minute.
public struct UsageQuery: Equatable {
    public var refresh = false
    public var days = 30
    public var provider = UsageProviderFilter.all
    public var source = UsageSourceFilter.all
    public var search = ""
    public var account: String?

    public init(refresh: Bool = false, days: Int = 30, provider: UsageProviderFilter = .all, source: UsageSourceFilter = .all, search: String = "", account: String? = nil) {
        self.refresh = refresh
        self.days = days
        self.provider = provider
        self.source = source
        self.search = search
        self.account = account
    }

    /// The request's fields; the host's defaults (30 days, all) are not sent.
    var wire: String {
        var fields = ""
        if refresh { fields += ",\"refresh\":true" }
        if days != 30 { fields += ",\"days\":\(days)" }
        if provider != .all { fields += ",\"provider\":\"\(provider.rawValue)\"" }
        if source != .all { fields += ",\"source\":\"\(source.rawValue)\"" }
        let word = search.trimmingCharacters(in: .whitespaces)
        if word.isEmpty == false { fields += ",\"search\":" + jsonString(word) }
        if let account { fields += ",\"account\":" + jsonString(account) }
        return fields
    }
}

public enum UsageProviderFilter: String, CaseIterable { case all, claude, codex, agy, local }
public enum UsageSourceFilter: String, CaseIterable { case all, epic, chat, external }
public enum UsageMetric: String, CaseIterable { case cost, tokens }

/// A price the person sets for a model: `local` is `$0.00`, `alias` borrows a catalog model's rates, `rates` gives its own (US dollars per
/// million tokens; the cached ones are optional), `clear` goes back to the table.
public struct UsageOverride: Equatable {
    public enum Action: Equatable {
        case local
        case alias(String)
        case rates(input: Double, cachedInput: Double?, cacheWrite: Double?, output: Double)
        case clear
    }

    public let model: String
    public let action: Action

    public init(model: String, action: Action) {
        self.model = model
        self.action = action
    }

    var wire: String {
        var fields = ",\"model\":" + jsonString(model)
        switch action {
        case .local: fields += ",\"action\":\"local\""
        case .clear: fields += ",\"action\":\"clear\""
        case .alias(let to): fields += ",\"action\":\"alias\",\"aliasTo\":" + jsonString(to)
        case .rates(let input, let cachedInput, let cacheWrite, let output):
            fields += ",\"action\":\"custom\",\"inputPerMillionUsd\":\(input),\"outputPerMillionUsd\":\(output)"
            if let cachedInput { fields += ",\"cachedInputPerMillionUsd\":\(cachedInput)" }
            if let cacheWrite { fields += ",\"cacheWritePerMillionUsd\":\(cacheWrite)" }
        }
        return fields
    }
}

/// What a person is told when the chat host that is running is older than the app and has no usage (or no price overrides): the app
/// replaces an older host when no session is working, so the way out is to finish the work and restart the host.
public let usageNeedsNewerHost = "The chat host that is running is older than this app and does not have Usage. Restart the chat host (when no session is working) to use it."
