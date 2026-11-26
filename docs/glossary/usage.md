# Usage

**Live quota** - The remaining capacity, rolling windows (such as five-hour, weekly or per-model pools) and reset times reported by a cloud harness or provider for an account in `providers.json`. It reflects everything consumed against that account inside and outside Carrier, and does not apply to local model providers (`lmstudio`, `ollama`).
_Avoid_: usage (too broad), historical spend, local tokens.

**Extra credits** - A prepaid or overage monetary balance on an account beyond its rolling subscription window (such as Claude `extra_usage`, Codex `credits` or Antigravity AI credits), reported by the provider when exposed natively. It is distinct from estimated API cost.
_Avoid_: estimated cost, API-equivalent spend, subscription quota.

**Estimated API cost** - The notional USD value computed from historical token counts and a model price table; for fixed-plan subscriptions it is a reference figure rather than billed spend, and for local model providers it is zero.
_Avoid_: bill, invoice, credits, real spend.
