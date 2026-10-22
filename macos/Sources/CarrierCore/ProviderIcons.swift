import Foundation

// The mark of the provider behind an agent (Claude, Codex, Antigravity): LobeHub Icons (MIT) bundled as SVGs in
// `Resources/ProviderIcons`. A provider without one keeps its letter.

/// The bundled SVG for an agent's display name (`agentName`), or nil when there is none.
public func providerIconURL(_ agent: String) -> URL? {
    Bundle.module.url(forResource: agent.lowercased(), withExtension: "svg", subdirectory: "ProviderIcons")
}
