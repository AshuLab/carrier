import AppKit
import CarrierCore
import SwiftUI

// The New sessions here group of a project's screen: what a session started in the project begins with.

extension ProjectDetailView {
    /// A value of `defaults` as a select's: nil is the first entry, and choosing it takes the key out of the file.
    func defaultBinding(_ key: ProjectDefaultKey, _ value: String?) -> Binding<String?> {
        Binding(get: { value }, set: { new in Task { await model.setDefault(key, new, path: row.path) } })
    }

    /// What a new session here starts with, as the project's entry has it; no agent is the same as everywhere.
    private var projectStart: NewSessionStart {
        let own = row.defaults
        return NewSessionStart(agent: own.agent ?? "", model: own.model ?? "", effort: own.effort ?? "", access: own.access)
    }

    /// The same panel as Settings > Sessions: provider, model, reasoning and access. Its first row is "Same as everywhere", which writes nothing.
    var startPicker: some View {
        let own = projectStart
        let access = NewSessionStart.json(fromAccess: own.access)
        return ModelPickerButton(
            provider: own.agent.isEmpty ? nil : own.agent, model: own.model.isEmpty ? nil : own.model, effort: own.effort,
            accounts: startPickerAccounts(catalog), catalog: catalog, showsAccess: false,
            accessScales: accessScalesOfStart(catalog: catalog, agent: own.agent.isEmpty ? everywhereAgent : own.agent, access: access),
            chooseAccess: { option, value in
                var start = namedStart()
                start.access[option] = value
                Task { await model.setStart(start, path: row.path) }
            },
            effortFallback: (label: Copy.projectsSameAsEverywhere(), detail: Copy.projectsFollowsSessionsDetail()), inherited: PickerInherited(
                provider: everywhereAgent.isEmpty ? nil : everywhereAgent, model: everywhereModel.isEmpty ? nil : everywhereModel,
                effort: everywhereEffort.isEmpty ? nil : everywhereEffort, follows: Copy.projectsFollowsSessions()
            ),
            allowsDefaultModel: true
        ) { pick in
            var start = projectStart
            switch pick {
            case .account(let agent, let model):
                // the reasoning and access are the provider's own: another provider starts over
                if agent != start.agent { start.effort = ""; start.access = [:] }
                start.agent = agent
                start.model = model ?? ""
            case .effort(let level):
                start = namedStart()
                start.effort = level
            case .inherit, .none: start = NewSessionStart()
            }
            Task { await model.setStart(start, path: row.path) }
        }
        .task { await catalog.load() }
    }

    /// The project's start with an agent named: one still on "Same as everywhere" takes what that is now (the first provider that can work when
    /// Settings > Sessions names none), so a reasoning or access level can be set on it.
    private func namedStart() -> NewSessionStart {
        var start = projectStart
        guard start.agent.isEmpty else { return start }
        start.agent = everywhereAgent.isEmpty ? (catalog.agents.first { $0.found }?.name ?? "") : everywhereAgent
        start.model = start.agent == everywhereAgent ? everywhereModel : ""
        return start
    }

    var workInOptions: [(value: String?, title: String)] {
        [(nil, Copy.projectsDefault())] + ProjectPage(for: row).workIn.map { ($0.projectValue, $0 == .baseFolder ? Copy.projectsWorkInBaseFolder() : Copy.projectsWorkInNewWorktree()) }
    }

    var branchOptions: [(value: String?, title: String)] {
        var names: [String] = []
        for branch in branches {
            let name = branch.remote && branch.name.hasPrefix("origin/") ? String(branch.name.dropFirst("origin/".count)) : branch.name
            if names.contains(name) == false { names.append(name) }
        }
        if let named = row.defaults.baseBranch, names.contains(named) == false { names.append(named) }
        return [(nil, Copy.projectsDefaultBranch())] + names.map { ($0, $0) }
    }
}
