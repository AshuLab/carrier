import Foundation

// The one button of the message box (docs/research/macos-app-design/explorations/composer-model-menu-sliders.html): its pill and its panel
// are drawn from the options the provider lists. The models are a list, the reasoning and the access are scales.

/// An option drawn as a slider: its values in order, the current one ticked.
public struct OptionScale: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let steps: [OptionRow.Choice]

    public init(id: String, title: String, steps: [OptionRow.Choice]) {
        self.id = id
        self.title = title
        self.steps = steps
    }

    public var index: Int { steps.firstIndex { $0.ticked } ?? 0 }
    public var current: OptionRow.Choice? { steps.first { $0.ticked } }
    /// An option with two values is a switch, not a slider: the second (the freer) is "on".
    public var isSwitch: Bool { steps.count == 2 }
}

public struct ComposerMenu: Equatable {
    public let models: [OptionRow.Choice]
    /// Nil for a model with no reasoning levels, or while the provider lists none.
    public let reasoning: OptionScale?
    /// One scale per option about what the agent may do: Claude's permission mode, or Codex's approvals and sandbox.
    public let access: [OptionScale]

    /// The model in the pill; "Default (recommended)" is "Default" there.
    public var pillModel: String? { models.first(where: \.ticked)?.label.replacingOccurrences(of: " (recommended)", with: "") }
    public var pillReasoning: String? { reasoning?.current?.label }

    /// The access the pill points out: the first scale that is freer than the careful value its provider starts with, nil when none is.
    public var accessFlag: String? {
        access.first { scale in
            guard let safe = scale.steps.firstIndex(where: { $0.id == safeAccess[scale.id] }) else { return false }
            return scale.index > safe
        }?.current?.label
    }
}

/// The options about what the agent may do, with their values from the most careful to the freest, as far as the app knows them; a
/// value it does not know goes last, in the provider's order. The first value of each is also where the provider starts.
private let carefulFirst: [String: [String]] = [
    "permissionMode": ["plan", "default", "acceptEdits", "auto", "dontAsk"],
    "approvalPolicy": ["untrusted", "on-failure", "on-request", "never"],
    "sandbox": ["read-only", "workspace-write", "danger-full-access"],
]
private let safeAccess = ["permissionMode": "default", "approvalPolicy": "untrusted", "sandbox": "workspace-write"]

public func composerMenu(_ options: [ChatOption]) -> ComposerMenu {
    let rows = optionRows(options)
    let access = rows.compactMap { row -> OptionScale? in
        guard let order = carefulFirst[row.id] else { return nil }
        let rank = { (choice: OptionRow.Choice) in order.firstIndex(of: choice.id) ?? order.count }
        return OptionScale(id: row.id, title: row.id == "permissionMode" ? "Access" : row.label, steps: row.choices.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element))
    }
    let effort = rows.first { $0.id == "effort" }.flatMap { $0.choices.isEmpty ? nil : OptionScale(id: $0.id, title: "Reasoning", steps: $0.choices) }
    return ComposerMenu(models: rows.first { $0.id == "model" }?.choices ?? [], reasoning: effort, access: access)
}
