import Foundation

// The options of a session (docs/specs/sessions-in-the-app.md, "The conversation: the options"): the provider lists them in the
// `events` reply, each with its values and the current one; the app draws whatever comes and keeps no list of its own.

/// One option the provider offers, as the host's `events` reply lists it.
public struct ChatOption: Codable, Equatable {
    public struct Value: Codable, Equatable {
        public let id: String
        public let label: String
        /// What the value is, in a line, when the provider says (a model's description).
        public let detail: String?
        /// The exact thing the value stands for, when it is not what the id says (the model an alias resolves to).
        public let version: String?

        public init(id: String, label: String, detail: String? = nil, version: String? = nil) {
            self.id = id
            self.label = label
            self.detail = detail
            self.version = version
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
        /// A line on what it is: the provider's when it gave one, else ours for the values every provider has.
        public let detail: String?
        public let version: String?
        public let icon: String?
    }

    public let id: String
    public let label: String
    public let choices: [Choice]
}

/// One row per option, in the provider's order.
public func optionRows(_ options: [ChatOption]) -> [OptionRow] {
    options.map { option in
        OptionRow(id: option.id, label: option.label, choices: option.values.map { value in
            .init(
                id: value.id, label: choiceLabel(option: option.id, value: value.id, label: value.label), ticked: value.id == option.current,
                detail: value.detail ?? choiceDetail(option: option.id, value: value.id), version: value.version, icon: choiceIcon(option: option.id, value: value.id)
            )
        })
    }
}

/// The words of a value: a label the provider gave in lower case ("low", "xhigh") starts with a capital, and "xhigh" says what it is.
public func choiceLabel(option: String, value: String, label: String) -> String {
    if option == "effort", value == "xhigh" { return "Extra high" }
    guard let first = label.first, first.isLowercase else { return label }
    return first.uppercased() + label.dropFirst()
}

/// A line on a value every provider of that option shares (Claude's permission modes, the reasoning efforts); nil for the rest.
public func choiceDetail(option: String, value: String) -> String? {
    switch (option, value) {
    case ("permissionMode", "default"): "Asks before it edits a file or runs a command."
    case ("permissionMode", "acceptEdits"): "Edits files without asking; commands still ask."
    case ("permissionMode", "plan"): "Reads and plans; it changes nothing."
    case ("permissionMode", "auto"): "Decides by itself what is safe to do."
    case ("permissionMode", "dontAsk"): "Does not ask: what was not allowed beforehand is refused."
    case ("effort", "low"): "The quickest answers, with the least thinking."
    case ("effort", "medium"): "A balance of speed and thinking."
    case ("effort", "high"): "Thinks longer on harder work."
    case ("effort", "xhigh"): "Thinks a lot before it answers; slower."
    case ("effort", "max"): "The most thinking there is."
    default: nil
    }
}

/// The SF Symbol of a value, so a list can be told at a glance; nil for a value with none.
public func choiceIcon(option: String, value: String) -> String? {
    switch (option, value) {
    case ("permissionMode", "default"): "hand.raised"
    case ("permissionMode", "acceptEdits"): "pencil.line"
    case ("permissionMode", "plan"): "list.clipboard"
    case ("permissionMode", "auto"): "bolt.fill"
    case ("permissionMode", "dontAsk"): "exclamationmark.shield"
    case ("effort", "low"): "gauge.with.dots.needle.0percent"
    case ("effort", "medium"): "gauge.with.dots.needle.33percent"
    case ("effort", "high"): "gauge.with.dots.needle.67percent"
    case ("effort", "xhigh"): "gauge.with.dots.needle.100percent"
    case ("effort", "max"): "flame.fill"
    case ("model", "default"): "star.fill"
    case ("model", _): "cpu"
    default: nil
    }
}

/// Where a session's options are kept between runs of the app: a closed session lists nothing (its agent does not run), so the box
/// shows what the session offered the last time the app saw it running.
public struct OptionsMemory: Sendable {
    public var load: @Sendable (String) -> [ChatOption]
    public var save: @Sendable (String, [ChatOption]) -> Void
    public var loadCommands: @Sendable (String) -> [ChatCommand]
    public var saveCommands: @Sendable (String, [ChatCommand]) -> Void
    public var loadAgent: @Sendable (String) -> String
    public var saveAgent: @Sendable (String, String) -> Void

    public init(
        load: @escaping @Sendable (String) -> [ChatOption], save: @escaping @Sendable (String, [ChatOption]) -> Void,
        loadCommands: @escaping @Sendable (String) -> [ChatCommand] = { _ in [] }, saveCommands: @escaping @Sendable (String, [ChatCommand]) -> Void = { _, _ in },
        loadAgent: @escaping @Sendable (String) -> String = { _ in "" }, saveAgent: @escaping @Sendable (String, String) -> Void = { _, _ in }
    ) {
        self.load = load
        self.save = save
        self.loadCommands = loadCommands
        self.saveCommands = saveCommands
        self.loadAgent = loadAgent
        self.saveAgent = saveAgent
    }

    /// Remembers nothing: for the tests.
    public static let none = OptionsMemory(load: { _ in [] }, save: { _, _ in })

    /// The app's own: user defaults, one entry per session.
    public static let userDefaults = OptionsMemory(
        load: { id in UserDefaults.standard.data(forKey: "chat.options.\(id)").flatMap { try? JSONDecoder().decode([ChatOption].self, from: $0) } ?? [] },
        save: { id, options in UserDefaults.standard.set(try? JSONEncoder().encode(options), forKey: "chat.options.\(id)") },
        loadCommands: { id in UserDefaults.standard.data(forKey: "chat.commands.\(id)").flatMap { try? JSONDecoder().decode([ChatCommand].self, from: $0) } ?? [] },
        saveCommands: { id, commands in UserDefaults.standard.set(try? JSONEncoder().encode(commands), forKey: "chat.commands.\(id)") },
        loadAgent: { id in UserDefaults.standard.string(forKey: "chat.agent.\(id)") ?? "" },
        saveAgent: { id, agent in UserDefaults.standard.set(agent, forKey: "chat.agent.\(id)") }
    )
}
