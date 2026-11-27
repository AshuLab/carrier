import Foundation
import Observation

extension NewSessionModel {
    /// Reads the agents and the recent folders again, each time the draft opens. A host that does not answer is started (the + is always
    /// on, so this is where it comes up) and asked once more; one that still does not answer leaves what was there.
    public func load() async {
        reopen()
        do {
            do { try await read() } catch {
                guard await ensureHost() else { throw error }
                try await read()
            }
        } catch {
            log("new session: \(ConversationModel.refusal(error).text)")
        }
        pickAvailableAgent()
        if let plan = restoring {
            restoring = nil
            await apply(plan)
        } else if let path = startFolder {
            startFolder = nil
            let branch = startBranchName
            startBranchName = nil
            await choose(folder: path)
            if let branch { await cutWorktree(from: branch) }
        }
    }

    /// The + of a workspace in the sidebar: the draft opens (or starts over, if it is open) with that folder chosen.
    public func start(in path: String) {
        startFolder = path
        startBranchName = nil
        starts += 1
    }

    /// The same for "New session on <branch>" of a session's menu: the draft opens with the folder chosen and a new worktree cut from that branch.
    public func start(in path: String, branch: String?) {
        startFolder = path
        startBranchName = branch
        starts += 1
    }

    /// A worktree cut from `branch`, on the side of it the folder has (its local branch, else the remote one); a folder that has no such branch, or
    /// offers no worktree, keeps the draft as the project sets it.
    private func cutWorktree(from branch: String) async {
        guard let workspace, workspace.branches.isEmpty == false else { return }
        if workspace.branches.contains(where: { $0.name == branch && $0.remote == false }) {
            choose(startBranch: branch, on: .local)
        } else if workspace.branches.contains(where: { $0.remote && $0.name == "origin/" + branch }) {
            choose(startBranch: branch, on: .remote)
        } else {
            return
        }
        await useWorktree(true)
    }

    /// A cancelled preparation gives the plan back: the draft that loads next has the folder, the branch or the worktree, the agent and its
    /// options and the text it was sent with, so nothing typed is lost.
    public func restore(_ plan: SessionPlan) { restoring = plan }

    private func apply(_ plan: SessionPlan) async {
        switch plan.workspace {
        case .folder(let path): await choose(folder: path)
        case .repo(let name): await choose(repo: name)
        case .newProject(let name): choose(newProject: name)
        }
        // the plan's text goes first and what was already written stays under it, as `editQueued` does; the pastes and files stay with their text
        text = text.isEmpty ? plan.text : plan.text + "\n" + text
        if agents.contains(where: { $0.name == plan.agent && $0.available }) { agent = plan.agent }
        restoredOptions = plan.options
        if let wanted = plan.worktree {
            picked = wanted.from
            chosenStart = wanted.startFrom
            await useWorktree(true)
            // an empty name is the host's to generate, which the draft already did
            if let name = wanted.name, name.isEmpty == false, worktree { worktreeName = name }
        } else {
            // the plan asked for the base folder: what it was sent with wins over "Work in"
            await useWorktree(false)
            if let branch = plan.branch { picked = branch }
        }
    }

    /// Every opening of New session starts here: no workspace (nor the branch and worktree that depend on it) and nothing the last opening
    /// left half done, except what the person wrote (the text, the pasted texts and the files): it stays until it is sent. The agent and its
    /// options are the person's taste, not part of where the session works, and stay.
    public func reopen() {
        clearWorkspace()
        refusal = nil
    }

    /// After a send, nothing of it is left: `reopen`, and no text either.
    public func blank() {
        reopen()
        text = ""
        pastes = []
        files = []
    }

    /// The workspace chip's ✕: drops the workspace and what depends on it (branch, worktree choice and name).
    public func clearWorkspace() { reset(folder: nil) }

    /// Keeps the chosen provider while it can be chosen, else takes the one Settings > Sessions names when it can work, else the first one
    /// that can; none when none can.
    public func pickAvailableAgent() {
        guard agents.contains(where: { $0.name == agent && $0.available }) == false else { return }
        let wanted = start().agent
        agent = agents.first(where: { $0.name == wanted && $0.available })?.name ?? agents.first(where: \.available)?.name
    }

    /// Why no provider can start a session, when the host listed some and none can; nil otherwise.
    public var noAgentReason: String? {
        guard agents.isEmpty == false, agents.contains(where: \.available) == false else { return nil }
        let reasons = agents.map {
            Copy.newSessionAgentIs(name: $0.name, note: $0.note(bundle: bundle, locale: locale) ?? Copy.newSessionAgentUnavailable(bundle: bundle, locale: locale), bundle: bundle, locale: locale)
        }
        return Copy.newSessionNoProvider(reasons: reasons.joined(separator: ", "), bundle: bundle, locale: locale)
    }

    func read() async throws {
        listed = try await host.agents()
        recent = recentFolders(try await host.list(archived: false) + (try await host.list(archived: true)))
        let capabilities = try await host.capabilities()
        hostOlder = capabilities.contains(.plan) == false
        hostCreates = capabilities.contains(.createProject)
        hostStarts = capabilities.contains(.worktreeStart)
        hostFetchesIfStale = capabilities.contains(.fetchIfStale)
    }

    /// Lists what the chosen agent offers: what was kept for it shows at once and the host is asked again in the background, so the list
    /// follows any change; with nothing kept the selects say they are reading until it answers. A new agent starts from its own values: what
    /// was chosen for the other is dropped. A host that cannot list them, or fails, leaves the kept list (or none) and the draft goes on.
    public func loadOptions() async {
        defer { takeRestoredOptions() }
        guard let name = agent, optionsAgent != name else { return }
        optionsAgent = name
        chosenOptions = [:]
        // what Settings > Sessions names: the model and reasoning go to the provider it names, the access to any provider that lists those options,
        // all as far as the provider lists them
        let wanted = startForNewSession()
        if restoredOptions == nil {
            let own = wanted.agent == name ? ["model": wanted.model, "effort": wanted.effort].filter { $0.value.isEmpty == false } : [:]
            restoredOptions = wanted.access.merging(own) { _, own in own }
        }
        let known = offers.offer(name)
        agentOptions = known?.options ?? []
        agentCommands = known?.commands ?? []
        loadingOptions = known == nil
        takeRestoredOptions()
        do {
            let listed = try await offers.refresh(name, host: host)
            guard optionsAgent == name else { return }
            agentOptions = listed.options
            agentCommands = listed.commands
        } catch {
            guard optionsAgent == name else { return }
            log("new session: could not list the options of \(name): \(ConversationModel.refusal(error).text)")
            optionsAgent = nil  // asked again the next time
        }
        loadingOptions = false
    }

    /// The options of a restored plan, as far as the agent lists them.
    private func takeRestoredOptions() {
        guard let wanted = restoredOptions, loadingOptions == false, agent == optionsAgent else { return }
        restoredOptions = nil
        // the model first: the reasoning levels are the chosen model's, so its effort is checked against them
        if let model = wanted["model"] { choose(option: "model", value: model) }
        for (option, value) in wanted where option != "model" { choose(option: option, value: value) }
    }

    /// What the selects list: the agent's options with the person's choices on top.
    public var shownOptions: [ChatOption] {
        let picked = chosenModel
        let levels = picked?.efforts ?? []
        // a model that lists no levels has no reasoning option, as in the host
        return agentOptions.filter { $0.id != "effort" || picked?.efforts?.isEmpty != true }.map { option in
            var values = option.values
            var current = option.current
            // the levels of the model chosen here, not those of the one the host opened its probe session with; a model other than that one
            // starts on its own default, and with none named the host's current stays (the host knows it, we do not guess one)
            if option.id == "effort", levels.isEmpty == false {
                values = levels.map { .init(id: $0, label: $0) }
                let probed = agentOptions.first { $0.id == "model" }?.current
                if picked?.id != probed, let fallback = picked?.defaultEffort { current = fallback }
            }
            return ChatOption(id: option.id, label: option.label, values: values, current: chosenOptions[option.id] ?? current)
        }
    }

    /// The model picked in this draft, as the agent lists it; nil while none is picked.
    private var chosenModel: ChatOption.Value? {
        guard let id = chosenOptions["model"] else { return nil }
        return agentOptions.first { $0.id == "model" }?.values.first { $0.id == id }
    }

    /// Chooses a value of an option the agent lists; one it does not list is not taken.
    public func choose(option: String, value: String) {
        guard shownOptions.contains(where: { $0.id == option && $0.values.contains { $0.id == value } }) else { return }
        chosenOptions[option] = value
        // a level the new model does not take cannot stay chosen
        if option == "model", let kept = chosenOptions["effort"], shownOptions.first(where: { $0.id == "effort" })?.values.contains(where: { $0.id == kept }) == false {
            chosenOptions["effort"] = nil
        }
    }

    /// The sheet opens: the projects folder and the repositories the engine watches are read again, so what it says about each is current.
    public func openPicker() {
        refreshWatched()
    }
}
