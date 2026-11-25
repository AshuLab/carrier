import Foundation

// Changing a global role (docs/specs/agents-in-settings.md): the pick the Agents page makes, sent as `EngineConfigChange.role`; the engine (src/config/role-edit.ts) writes `agents.<role>`
// of `engine.json`, plus the profile a chosen identity needs, and nothing else.

/// The one thing the person changed in a role.
public enum RoleChange: Equatable, Sendable {
    /// a bot of the Agent Forge registry: writes (or reuses) the profile `{ kind: "forge", agent: <name> }`
    case bot(String)
    /// the person's own login: the profile `{ kind: "gh" }`
    case gh
    case provider(String)
    case model(String)
    /// nil: none, the CLI's own default
    case effort(String?)
}
