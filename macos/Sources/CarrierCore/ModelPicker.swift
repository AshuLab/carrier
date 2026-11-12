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
}

/// The models of an offer. "Default" is left out: a role runs on a named model, and what the default is changes with the CLI.
public func modelOptions(_ offer: AgentOffer?) -> [ModelOption] {
    guard let offer else { return [] }
    return composerMenu(offer.options).models.filter { $0.id != "default" }.map { choice in
        let version = choice.version.flatMap { $0.lowercased() == choice.label.lowercased() ? nil : $0 }
        return ModelOption(id: choice.id, label: choice.label, detail: choice.detail ?? version)
    }
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
