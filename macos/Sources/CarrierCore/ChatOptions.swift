import Foundation

// The options of a session (docs/specs/sessions-in-the-app.md, "The conversation: the options"): the provider lists them in the
// `events` reply, each with its values and the current one; the app draws whatever comes and keeps no list of its own.

/// One option the provider offers, as the host's `events` reply lists it.
public struct ChatOption: Decodable, Equatable {
    public struct Value: Decodable, Equatable {
        public let id: String
        public let label: String

        public init(id: String, label: String) {
            self.id = id
            self.label = label
        }
    }

    public let id: String
    public let label: String
    public let values: [Value]
    public let current: String

    public init(id: String, label: String, values: [Value], current: String) {
        self.id = id
        self.label = label
        self.values = values
        self.current = current
    }

    /// The label of the current value; the value's own id when the provider does not list it.
    public var currentLabel: String { values.first { $0.id == current }?.label ?? current }
}

/// The text of the pill: the current values in the order the provider lists them ("Sonnet · High · Ask first"); nil when it lists none.
public func optionsPill(_ options: [ChatOption]) -> String? {
    options.isEmpty ? nil : options.map(\.currentLabel).joined(separator: " · ")
}

/// A row of the panel: the option's label and the menu of its values, the current one ticked.
public struct OptionRow: Equatable, Identifiable {
    public struct Choice: Equatable, Identifiable {
        public let id: String
        public let label: String
        public let ticked: Bool
    }

    public let id: String
    public let label: String
    public let choices: [Choice]
}

/// One row per option, in the provider's order.
public func optionRows(_ options: [ChatOption]) -> [OptionRow] {
    options.map { option in
        OptionRow(id: option.id, label: option.label, choices: option.values.map { .init(id: $0.id, label: $0.label, ticked: $0.id == option.current) })
    }
}
