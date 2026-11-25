import Foundation
import Observation

/// How full a session's context is: what its last turn ended with and the size of the model's window, when the host said both.
public struct ContextUse: Equatable {
    public var tokens: Double
    public var window: Double?

    public init(tokens: Double, window: Double? = nil) { (self.tokens, self.window) = (tokens, window) }

    /// The share of the window in use, `0...1`; nil without a window.
    public var share: Double? { window.flatMap { $0 > 0 ? min(tokens / $0, 1) : nil } }

    /// `45.7k of 1M`; just the count when the window is not known.
    public func text(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        window.map { Copy.chatContextOf(used: Self.count(tokens), window: Self.count($0), bundle: bundle, locale: locale) } ?? Self.count(tokens)
    }

    private static func count(_ tokens: Double) -> String {
        tokens >= 1_000_000 ? String(format: "%g", (tokens / 100_000).rounded() / 10) + "M" : TurnSummary.tokens(tokens)
    }
}

/// The context of the last turn that told it (a turn that was cut short, or a host that does not say it, leaves the one before).
public func contextUse(_ rows: [FeedRow]) -> ContextUse? {
    for (index, row) in rows.enumerated().reversed() {
        // a `/clear` emptied it: what the turns before it read is not the context any more
        if case .cleared = row { return nil }
        // a summary left what it says (the window is the model's, as the turns before it told it); a failed one left it as it was
        if case .compacted(_, let cut) = row, cut.error == nil {
            guard let left = cut.after else { return nil }
            let window = rows[..<index].reversed().lazy.compactMap { row -> Double? in if case .turnEnd(_, let summary) = row { summary.contextWindow } else { nil } }.first
            return ContextUse(tokens: left, window: window)
        }
        if case .turnEnd(_, let summary) = row, let tokens = summary.contextTokens { return ContextUse(tokens: tokens, window: summary.contextWindow) }
    }
    return nil
}

/// "claude-sonnet-5-5 · 12s · 1.8k in · 436 out": each part only when the host or the provider gave it.
/// What closes a turn: the model, how long it took and the tokens the provider reported. `text` is all of it as one line.
public struct TurnSummary: Equatable {
    public var model: String?
    public var duration: String?
    /// What the model read: the new input and what came from the cache (most of it once a session has a history).
    public var input: Double?
    public var cacheRead: Double?
    public var cacheWrite: Double?
    public var output: Double?
    /// What the turn's last model call read: the context at the turn's end. The three counts above add every call of the turn up, and each call
    /// reads the whole context again, so they are many times it; nil from a host that does not say it.
    public var contextTokens: Double?
    /// The size of the model's window, which says how full `contextTokens` is; nil from a host that does not say it.
    public var contextWindow: Double?

    public init(model: String? = nil, duration: String? = nil, input: Double? = nil, cacheRead: Double? = nil, cacheWrite: Double? = nil, output: Double? = nil, contextTokens: Double? = nil, contextWindow: Double? = nil) {
        (self.model, self.duration, self.input, self.cacheRead, self.cacheWrite, self.output) = (model, duration, input, cacheRead, cacheWrite, output)
        (self.contextTokens, self.contextWindow) = (contextTokens, contextWindow)
    }

    init?(_ end: ChatEvent, turnStart: Int?) {
        func count(_ keys: String...) -> Double? { keys.lazy.compactMap { end.usage?[$0] }.first }
        self.init(
            model: end.model, duration: turnStart.map { formatDuration(end.at - $0) },
            input: count("input_tokens", "inputTokens"), cacheRead: count("cache_read_input_tokens", "cacheReadInputTokens"),
            cacheWrite: count("cache_creation_input_tokens", "cacheCreationInputTokens"), output: count("output_tokens", "outputTokens"),
            contextTokens: count("context_tokens", "contextTokens"), contextWindow: count("context_window", "contextWindow")
        )
        // nothing to say: no model or duration worth a word, and no count
        if [shortModel, duration].compactMap({ $0 }).allSatisfy(\.isEmpty), contextTokens == nil, read == nil, output == nil { return nil }
    }

    /// Everything the turn's model calls read added up, nil when the provider reported none of it.
    public var read: Double? {
        let reads = [input, cacheRead, cacheWrite].compactMap { $0 }
        return reads.isEmpty ? nil : reads.reduce(0, +)
    }

    /// `181.2k context`: the context at the turn's end. A host that does not say it (an older one, or a turn it stored before) leaves only what the
    /// calls read added up, which is not the context and is not called that: `540.1k in`.
    public func contextText(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        if let contextTokens { return Copy.chatContextTokens(count: Self.tokens(contextTokens), bundle: bundle, locale: locale) }
        return read.map { Copy.chatContextIn(count: Self.tokens($0), bundle: bundle, locale: locale) }
    }

    /// `436 out`: what the model wrote.
    public func outText(bundle: Bundle? = nil, locale: Locale = .current) -> String? {
        output.map { Copy.chatTokensOut(count: Self.tokens($0), bundle: bundle, locale: locale) }
    }

    /// The tooltip of the numbers: the context at the end of the turn, then what all its model calls read and wrote added up (each call reads the whole
    /// context again, most of it from the cache, so these are many times the context).
    public func breakdown(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        let total = [
            input.map { Copy.chatBreakdownInput(count: Int($0), bundle: bundle, locale: locale) },
            cacheRead.map { Copy.chatBreakdownCacheRead(count: Int($0), bundle: bundle, locale: locale) },
            cacheWrite.map { Copy.chatBreakdownCacheWrite(count: Int($0), bundle: bundle, locale: locale) },
            output.map { Copy.chatBreakdownOutput(count: Int($0), bundle: bundle, locale: locale) },
        ].compactMap { $0 }
        let context = contextTokens.map { [Copy.chatBreakdownContext(count: Int($0), bundle: bundle, locale: locale)] } ?? []
        let calls = Copy.chatBreakdownCalls(bundle: bundle, locale: locale)
        let header = total.isEmpty ? [] : [context.isEmpty ? calls : "\n" + calls]
        return (context + header + total).joined(separator: "\n")
    }

    /// `12`, `2.5k`: a count as the line writes it.
    public static func tokens(_ count: Double) -> String { count < 1000 ? "\(Int(count))" : String(format: "%.1fk", count / 1000) }

    public func text(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        [shortModel, duration, contextText(bundle: bundle, locale: locale), outText(bundle: bundle, locale: locale)].compactMap { $0 }.joined(separator: " · ")
    }

    /// The model as a person says it: `claude-haiku-5-5` is `haiku 5.5`, and a dated one (`claude-opus-4-1-20250805`) loses its date. A name
    /// that is not Claude's, or not in that shape, stays as it came.
    public var shortModel: String? {
        guard let model else { return nil }
        guard model.hasPrefix("claude-") else { return model }
        var parts = model.dropFirst("claude-".count).split(separator: "-").map(String.init)
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        guard let family = parts.first, parts.dropFirst().allSatisfy({ $0.allSatisfy(\.isNumber) }), parts.count > 1 else { return model }
        return "\(family) \(parts.dropFirst().joined(separator: "."))"
    }
}

/// The closing line of a turn that ends right after an agent message, taken out of the feed and handed to that message by its id: the
/// message shows it (on hover) as part of itself. A closing line after anything else stays a row.
public func foldingClosingLines(_ rows: [FeedRow]) -> (rows: [FeedRow], lines: [String: TurnSummary]) {
    var kept: [FeedRow] = []
    var lines: [String: TurnSummary] = [:]
    for row in rows {
        if case .turnEnd(_, let summary) = row, case .agent(let id, _, _)? = kept.last {
            lines[id] = summary
        } else {
            kept.append(row)
        }
    }
    return (kept, lines)
}
