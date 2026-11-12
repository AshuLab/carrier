import Foundation

// What the Agents page's model picker lists: the accounts that can work now, the models a provider offers and the reasoning levels a role takes.
// The picker is the same panel the chat's message box has (providers as tabs, a search, the models, the reasoning slider), for a role of an epic.

/// The icon file of a harness: Antigravity's is `antigravity`, the others are named after the harness.
public func providerIconName(harness: String) -> String { harness == "agy" ? "antigravity" : harness }

/// An account as a tab of the picker.
public struct PickerAccount: Equatable, Identifiable {
    public var name: String
    /// the harness the account runs, which says what models it offers; empty when it is not known
    public var harness: String
    public var icon: String
    /// signed in and found: the others are shown only when a role already names them
    public var ready: Bool
    public var id: String { name }
}

/// The accounts to offer: the ones `providers` says are ready, and `current` when a role already names it, even when it cannot work now (it
/// stays, marked, so what the file says is not hidden). With no answer from the host (not running, too old) every declared account is offered,
/// since nothing says it is not ready. `icons` is `accountIcons`: the mark of each account by its harness.
public func pickerAccounts(_ reply: HostProviders?, declared: [String], icons: [String: String], current: [String]) -> [PickerAccount] {
    func harness(of name: String, in reply: HostProviders?) -> String {
        if let found = reply?.accounts.first(where: { $0.name == name }) { return found.harness }
        // no answer: the icon names the harness back
        return icons[name].map { $0 == "antigravity" ? "agy" : $0 } ?? name
    }
    func account(_ name: String, ready: Bool) -> PickerAccount {
        let harness = harness(of: name, in: reply)
        return PickerAccount(name: name, harness: harness, icon: icons[name] ?? providerIconName(harness: harness), ready: ready)
    }
    guard let reply, reply.problem == nil else { return declared.map { account($0, ready: true) } }
    var names = reply.accounts.filter { $0.state == .ready }.map(\.name)
    for name in current where name.isEmpty == false && names.contains(name) == false { names.append(name) }
    return names.map { name in account(name, ready: reply.accounts.first { $0.name == name }?.state == .ready) }
}

/// A model a provider offers, as a row of the list.
public struct ModelOption: Equatable, Identifiable {
    public var id: String
    public var label: String
    /// what the provider says about it, else its exact name when that says more than the label
    public var detail: String?

    public init(id: String, label: String, detail: String? = nil) {
        self.id = id
        self.label = label
        self.detail = detail
    }
}

/// The models of an offer. "Default" is left out: a role runs on a named model, and what the default is changes with the CLI.
public func modelOptions(_ offer: AgentOffer?) -> [ModelOption] {
    guard let offer else { return [] }
    return composerMenu(offer.options).models.filter { $0.id != "default" }.map { choice in
        let version = choice.version.flatMap { $0.lowercased() == choice.label.lowercased() ? nil : $0 }
        return ModelOption(id: choice.id, label: choice.label, detail: choice.detail ?? version)
    }
}

/// The models `agy models` prints (the chat host has no adapter for Antigravity, so it lists none): a first line "Fetching available models...", then
/// `id<TAB>label` for each. A line with no tab is not a model.
public func parseAgyModels(_ output: String) -> [ModelOption] {
    output.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: "\t", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, parts[0].isEmpty == false, parts[0].contains(" ") == false else { return nil }
        return ModelOption(id: parts[0], label: parts[1], detail: nil)
    }
}

/// An Antigravity model family: `agy models` lists each family once per level of reasoning (`gemini-4-argon-low`, `-medium`, `-high`), and the level is
/// part of the model's id. The picker lists the family and lets the slider choose the level, so what is written is still the full id.
public struct AgyFamily: Equatable, Identifiable {
    public var id: String
    public var label: String
    /// the levels the family has, in the order `agy models` printed them
    public var levels: [String]
}

/// `gemini-4-argon-high` is the family `gemini-4-argon` at `high`; an id that does not end in a level is a family with none.
public func splitAgyID(_ id: String) -> (family: String, level: String?) {
    for level in roleEfforts where id.hasSuffix("-" + level) { return (String(id.dropLast(level.count + 1)), level) }
    return (id, nil)
}

/// The families of the models `parseAgyModels` read, in the order they first appear.
public func agyFamilies(_ models: [ModelOption]) -> [AgyFamily] {
    var families: [AgyFamily] = []
    for model in models {
        let (family, level) = splitAgyID(model.id)
        var label = model.label
        // "Gemini 4 Argon (High)": the level is the slider's, not the family's name
        if level != nil, label.hasSuffix(")"), let open = label.range(of: " (", options: .backwards) { label = String(label[..<open.lowerBound]) }
        if let index = families.firstIndex(where: { $0.id == family }) {
            if let level, families[index].levels.contains(level) == false { families[index].levels.append(level) }
        } else {
            families.append(AgyFamily(id: family, label: label, levels: level.map { [$0] } ?? []))
        }
    }
    return families
}

/// The id to write for a family: at the level the role had when the family has it, else the middle one, else the first; a family with no levels is
/// its own id.
public func agyModelID(_ family: AgyFamily, keeping level: String?) -> String {
    guard family.levels.isEmpty == false else { return family.id }
    let chosen = level.flatMap { family.levels.contains($0) ? $0 : nil } ?? (family.levels.contains("medium") ? "medium" : family.levels[0])
    return family.id + "-" + chosen
}

/// The chat agent whose offer lists a harness's models: the first one of that harness whose binary was found.
public func chatAgent(forHarness harness: String, among agents: [ChatAgent]) -> String? {
    agents.first { $0.harness == harness && $0.found }?.name
}

/// A level of a role's reasoning: "" is the CLI's own.
public struct EffortStep: Equatable {
    public var id: String
    public var label: String
    public var detail: String
}

public let effortSteps: [EffortStep] = [
    EffortStep(id: "", label: "Default", detail: "The CLI's own level, whatever it is today."),
    EffortStep(id: "low", label: "Low", detail: "The quickest answers, with the least thinking."),
    EffortStep(id: "medium", label: "Medium", detail: "Balanced: some thinking before it answers."),
    EffortStep(id: "high", label: "High", detail: "Thinks it through; slower and more careful."),
    EffortStep(id: "xhigh", label: "Extra high", detail: "A lot of thinking, for hard problems."),
    EffortStep(id: "max", label: "Max", detail: "The most thinking it can do; the slowest."),
]
