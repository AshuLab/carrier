import CarrierCore
import SwiftUI

/// The models each provider offers, for the Agents page's picker: asked of the chat host (the same list the message box shows) and kept in the
/// app's offer store, so the picker has them as soon as it opens.
@MainActor @Observable final class ModelCatalog {
    static let shared = ModelCatalog()

    private(set) var agents: [ChatAgent] = []
    private(set) var offers: [String: [ModelOption]] = [:]
    private(set) var loading = false
    /// The models of a harness the chat host does not serve, read from its own CLI (Antigravity's `agy models`).
    private(set) var cliModels: [String: [ModelOption]] = [:]

    /// What the provider with this harness offers; nil while nothing says (no host, or none asked yet).
    func models(forHarness harness: String) -> [ModelOption]? {
        if harness == "agy" {
            return cliModels["agy"].map { models in
                agyFamilies(models).map { ModelOption(id: $0.id, label: $0.label, detail: $0.levels.isEmpty ? nil : Copy.chatPickerLevels(levels: $0.levels.map(levelLabel).joined(separator: ", "))) }
            }
        }
        return chatAgent(forHarness: harness, among: agents).flatMap { offers[$0] }
    }

    func load() async {
        guard loading == false else { return }
        loading = true
        defer { loading = false }
        await loadAgyModels()
        let host = SocketChatHost()
        guard let found = try? await host.agents() else { return }
        agents = found
        for agent in found where agent.found {
            if let kept = AgentOfferStore.shared.offer(agent.name) { offers[agent.name] = modelOptions(kept) }
        }
        for agent in found where agent.found {
            if let offer = try? await AgentOfferStore.shared.refresh(agent.name, host: host) { offers[agent.name] = modelOptions(offer) }
        }
    }
}

extension ModelCatalog {
    /// Antigravity's families with their levels, for the slider.
    var agyFamilyList: [AgyFamily] { agyFamilies(cliModels["agy"] ?? []) }

    /// Antigravity's models: the chat host has no adapter for it, so its own CLI is asked, once, with the binary the Providers page found.
    fileprivate func loadAgyModels() async {
        guard cliModels["agy"] == nil else { return }
        if case .reply = AppHealth.providers.outcome {} else { await AppHealth.providers.load() }
        guard case .reply(let reply) = AppHealth.providers.outcome,
              let path = reply.accounts.first(where: { $0.harness == "agy" && $0.found })?.path else { return }
        let models = await AgyModels(runner: SystemProcessRunner()).load(binary: path, environment: ProcessInfo.processInfo.environment)
        if models.isEmpty == false { cliModels["agy"] = models }
    }
}

/// A level of reasoning in words ("xhigh" is "Extra high").
private func levelLabel(_ id: String) -> String { effortSteps().first { $0.id == id }?.label ?? id }

/// What a choice in the picker asks for.
enum ModelPick {
    /// an account and, with it, the model: they change together, since a model belongs to one provider
    case account(String, model: String?)
    /// a level of reasoning; "" is the CLI's own
    case effort(String)
    /// Follow what the role is everywhere else: no provider and no model of its own
    case inherit
    case none
}

/// What a role follows when it names nothing of its own (a repo's role follows the global one).
struct PickerInherited {
    var provider: String?
    var model: String?
    var effort: String?
    /// What it follows, in the words of the list's first row.
    var follows = Copy.chatPickerGlobalRole()

    var text: String { [provider, model, effort].compactMap { $0 }.filter { $0.isEmpty == false }.joined(separator: " · ") }
}

/// The model of a role, or of a step of its failover, as a pill with the provider's mark, the model and the reasoning; it opens the panel the
/// chat's message box has: the providers that can work as tabs, a search, the models and the reasoning slider. A role runs on its own, so the
/// panel says its access is full, where the chat lets the person choose it.
struct ModelPickerButton: View {
    @Environment(\.pieceTheme) private var theme
    let provider: String?
    let model: String?
    var effort: String?
    let accounts: [PickerAccount]
    let catalog: ModelCatalog
    var showsEffort = true
    /// The note that a role's access is full: the chat's panel leaves it out, since the person chooses the access there.
    var showsAccess = true
    /// With `showsAccess` off: the access options of the provider (the chat's sliders), by their option id, and what moving one asks for.
    var accessScales: [OptionScale] = []
    var chooseAccess: (String, String) -> Void = { _, _ in }
    /// A role that may name no effort (a failover step, a repo's role): the first level of the slider says what it then does.
    var effortFallback: (label: String, detail: String)?
    /// Set for a repo's role: the first row of the list is "Same as everywhere", and the pill shows what that is.
    var inherited: PickerInherited?
    /// The pill takes the width it is given (a form), where in a row it has a width of its own.
    var fill = false
    /// A step may name no model and take the account's own: the first row of the list says so, and so does the pill.
    var allowsDefaultModel = false
    /// Set for a step that may be taken away (the second): the row at the foot that does it.
    var noneTitle: String?
    var placeholder = Copy.chatPickerChoose()
    let pick: (ModelPick) -> Void

    @State private var open = false
    @State private var viewing: String?
    @State private var query = ""

    /// What the role is now: its own value, else what it follows.
    private var shownProvider: String? { provider ?? inherited?.provider }
    private var shownModel: String? { model ?? (provider == nil ? inherited?.model : nil) }
    private var shownEffort: String? { effort ?? inherited?.effort }
    private var followsAll: Bool { inherited != nil && provider == nil && model == nil }
    /// The account whose models are ticked: the role's own (a model of its own on the followed account counts for it).
    private var ownAccount: String? { provider ?? (model != nil ? inherited?.provider : nil) }

    private var current: PickerAccount? { accounts.first { $0.name == shownProvider } }
    /// Antigravity names the level of reasoning in the model's id: the list is of families and the slider picks the level.
    private var currentIsAgy: Bool { current?.harness == "agy" }
    /// The tab shown: the one the person went to, else the role's own account, else the first.
    private var shownName: String? { viewing ?? shownProvider ?? accounts.first?.name }

    var body: some View {
        Button {
            viewing = nil
            query = ""
            open.toggle()
        } label: { pill }
            .buttonStyle(SelectButtonStyle())
            .popover(isPresented: $open, arrowEdge: .bottom) { panel }
            .help(Copy.chatPickerHelp()).accessibilityLabel(Copy.chatPickerHelp())
            .accessibilityValue([shownProvider, modelText, effortText].compactMap { $0 }.joined(separator: ", "))
    }

    // MARK: the pill

    private var modelText: String? {
        guard shownProvider != nil else { return nil }
        guard let model = shownModel else { return allowsDefaultModel ? Copy.chatPickerDefaultModel() : nil }
        if currentIsAgy { return catalog.agyFamilyList.first { $0.id == splitAgyID(model).family }?.label ?? model }
        return current.flatMap { catalog.models(forHarness: $0.harness) }?.first { $0.id == model }.map { $0.label.replacingOccurrences(of: " (recommended)", with: "") } ?? model
    }

    private var effortText: String? {
        guard showsEffort, shownProvider != nil else { return nil }
        // for Antigravity the level is part of the model's id
        if currentIsAgy { return shownModel.flatMap { splitAgyID($0).level }.map(levelLabel) }
        if effortFallback != nil, (shownEffort ?? "").isEmpty { return nil }
        return effortSteps().first { $0.id == (shownEffort ?? "") }?.label
    }

    private var pill: some View {
        HStack(spacing: Tokens.Space.s8) {
            if let current { AccountMark(account: current.name, icon: current.icon, size: 14) }
            HStack(spacing: Tokens.Space.s5) {
                if followsAll {
                    Text(Copy.chatPickerSameEverywhere()).lineLimit(1)
                    Text("·").foregroundStyle(.secondary)
                }
                // whose model it is first (two logins of one provider have one mark), then the model, then how hard it thinks
                if let shownProvider {
                    Text(shownProvider).foregroundStyle(.secondary).lineLimit(1)
                    Text("·").foregroundStyle(.secondary)
                }
                Text(modelText ?? (shownProvider == nil ? placeholder : Copy.chatPickerNoModel())).lineLimit(1)
                if let effortText {
                    Text("·").foregroundStyle(.secondary)
                    Text(effortText).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            // the chevrons after the words, as the Mac's pop-up has them
            SelectChevron()
        }
        // in a form the words end at the right edge of the row, where the other selects do; long ones are cut
        .frame(maxWidth: fill ? .infinity : nil, alignment: .trailing)
    }

    // MARK: the panel

    private var panel: some View {
        VStack(spacing: Tokens.Space.none) {
            tabs
            search
            list
            if showsEffort {
                if currentIsAgy { agyReasoning } else { ScaleRow(
                    scale: OptionScale(id: "effort", title: Copy.chatComposerReasoning(), steps: effortSteps().map {
                        let fallback = $0.id.isEmpty ? effortFallback : nil
                        return OptionRow.Choice(id: $0.id, label: fallback?.label ?? $0.label, ticked: $0.id == (effort ?? ""), detail: fallback?.detail ?? $0.detail)
                    }),
                    color: { _, _ in theme.accent },
                    commit: { index in if effortSteps().indices.contains(index) { pick(.effort(effortSteps()[index].id)) } }
                ) }
                if showsAccess { accessNote } else {
                    ForEach(accessScales) { scale in
                        let commit: (Int) -> Void = { index in if scale.steps.indices.contains(index) { chooseAccess(scale.id, scale.steps[index].id) } }
                        if scale.isSwitch { SwitchRow(scale: scale, commit: commit) } else { ScaleRow(scale: scale, color: { index, count in riskColor(index, count) }, commit: commit) }
                    }
                }
            }
            if let noneTitle, shownProvider != nil {
                Button { pick(.none); open = false } label: { Label(noneTitle, icon: .close).labelStyle(.titleAndIcon).frame(maxWidth: .infinity, alignment: .leading) }
                    .buttonStyle(HoverTextButtonStyle(tint: nil)).padding(.horizontal, Tokens.Space.s12).padding(.vertical, Tokens.Space.s10)
                    .overlay(alignment: .top) { Divider() }
            }
        }
        .frame(width: 380, height: showsEffort ? 580 + 90 * CGFloat(accessScales.count) : 440)
        .writingToolsBehavior(.disabled)
        .task { await catalog.load() }
    }

    /// Antigravity's slider: the levels the family of the chosen model has, and moving it writes that family at the new level.
    @ViewBuilder private var agyReasoning: some View {
        let split = shownModel.map(splitAgyID)
        let family = catalog.agyFamilyList.first { $0.id == split?.family }
        let levels = family?.levels ?? []
        ScaleRow(
            scale: OptionScale(id: "effort", title: Copy.chatComposerReasoning(), steps: levels.map { level in
                OptionRow.Choice(id: level, label: levelLabel(level), ticked: level == split?.level, detail: effortSteps().first { $0.id == level }?.detail)
            }),
            note: levels.isEmpty ? Copy.chatComposerNoLevels() : nil,
            color: { _, _ in theme.accent },
            commit: { index in
                guard let family, let account = shownProvider, levels.indices.contains(index) else { return }
                pick(.account(account, model: family.id + "-" + levels[index]))
            }
        )
    }

    /// Only the providers that can work, one tab each; the tab is the account (two logins of one provider are two tabs, told apart by their
    /// names), and a dot marks the one the role has now.
    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Tokens.Space.s2) {
                ForEach(accounts) { account in
                    let on = account.name == shownName
                    Button { viewing = account.name; query = "" } label: {
                        VStack(spacing: Tokens.Space.s3) {
                            AccountMark(account: account.name, icon: account.icon, size: 18)
                            Text(ProviderIdentityStore.shared.shortName(of: account.name)).scaledFont(10, weight: .medium).lineLimit(1)
                        }
                        .frame(minWidth: 54).padding(.horizontal, Tokens.Space.s6).padding(.vertical, Tokens.Space.s6)
                        .overlay(alignment: .bottom) { if on { Capsule().fill(.primary).frame(height: 2).padding(.horizontal, Tokens.Space.s8) } }
                        .overlay(alignment: .topTrailing) {
                            if account.name == shownProvider { Circle().fill(.tint).frame(width: 6, height: 6).padding(.top, Tokens.Space.s5).padding(.trailing, Tokens.Space.s8) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).opacity(account.ready ? (on ? 1 : 0.7) : 0.4)
                    .help(account.ready ? account.name : Copy.chatPickerNotSignedIn(account: account.name))
                    .accessibilityLabel(account.name).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.horizontal, Tokens.Space.s12).padding(.top, Tokens.Space.s4)
        }
        .overlay(alignment: .bottom) { Divider() }
    }

    private var search: some View {
        TextField(Copy.chatPickerSearch(), text: $query).settingsField(icon: .search)
            .padding(.horizontal, Tokens.Space.s12).padding(.top, Tokens.Space.s10).padding(.bottom, Tokens.Space.s2)
    }

    private var viewed: PickerAccount? { accounts.first { $0.name == shownName } }

    @ViewBuilder private var list: some View {
        if let viewed {
            let options = catalog.models(forHarness: viewed.harness)
            let needle = query.trimmingCharacters(in: .whitespaces)
            let shown = (options ?? []).filter { needle.isEmpty || $0.label.localizedCaseInsensitiveContains(needle) || $0.id.localizedCaseInsensitiveContains(needle) }
            let isCurrent = viewed.name == ownAccount
            // a model the file names that the provider does not list stays, so what is written is seen
            let viewedIsAgy = viewed.harness == "agy"
            // for Antigravity the list is of families: the model's id is the family and a level
            let chosenId = model.map { viewedIsAgy ? splitAgyID($0).family : $0 }
            let custom = isCurrent ? model.flatMap { model in (options ?? []).contains { $0.id == (viewedIsAgy ? splitAgyID(model).family : model) } ? nil : model } : nil
            ScrollView {
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    if let inherited, needle.isEmpty {
                        row(title: Copy.chatPickerSameEverywhere(), detail: inherited.text.isEmpty ? Copy.chatPickerFollows(follows: inherited.follows) : Copy.chatPickerFollowsWith(follows: inherited.follows, text: inherited.text), ticked: followsAll) { pick(.inherit) }
                    }
                    if allowsDefaultModel, needle.isEmpty {
                        row(title: Copy.chatPickerDefaultModel(), detail: Copy.chatPickerDefaultDetail(account: viewed.name), ticked: isCurrent && model == nil) { pick(.account(viewed.name, model: nil)) }
                    }
                    if let custom, needle.isEmpty || custom.localizedCaseInsensitiveContains(needle) {
                        row(title: custom, detail: Copy.chatPickerNamedInFile(), ticked: true) { pick(.account(viewed.name, model: custom)) }
                    }
                    ForEach(shown) { option in
                        row(title: option.label, detail: option.detail, ticked: isCurrent && option.id == chosenId) {
                            if viewedIsAgy, let family = catalog.agyFamilyList.first(where: { $0.id == option.id }) {
                                pick(.account(viewed.name, model: agyModelID(family, keeping: model.flatMap { splitAgyID($0).level })))
                            } else {
                                pick(.account(viewed.name, model: option.id))
                            }
                        }
                    }
                    // a model the list does not have can still be used: the search words are taken as its name
                    if needle.isEmpty == false, (options ?? []).contains(where: { $0.id.lowercased() == needle.lowercased() }) == false, needle != custom {
                        row(title: Copy.chatPickerUse(name: needle), detail: Copy.chatPickerUseDetail(), ticked: false) { pick(.account(viewed.name, model: needle)) }
                    }
                    if options == nil {
                        Text(catalog.loading ? Copy.chatPickerLooking() : Copy.chatPickerNoList())
                            .scaledFont(12).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(Tokens.Space.s16)
                    } else if shown.isEmpty && needle.isEmpty && allowsDefaultModel == false && custom == nil {
                        Text(Copy.chatPickerNoModelsListed()).scaledFont(12).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(Tokens.Space.s16)
                    }
                }
                .padding(.horizontal, Tokens.Space.s8).padding(.vertical, Tokens.Space.s8)
            }
            .frame(maxHeight: .infinity)
        } else {
            Text(Copy.chatPickerNoProvider()).scaledFont(12).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(Tokens.Space.s20)
        }
    }

    private func row(title: String, detail: String?, ticked: Bool, action: @escaping () -> Void) -> some View {
        HoverRow(action: action, fill: ticked ? theme.accent.opacity(0.18) : nil) { _ in
            HStack(spacing: Tokens.Space.s8) {
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    Text(title).scaledFont(13, weight: .medium).lineLimit(1)
                    if let detail { Text(detail).scaledFont(11.5).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 8)
                if ticked { ChosenMark() }
            }
            .padding(.horizontal, Tokens.Space.s10).padding(.vertical, Tokens.Space.s8)
        }
    }

    /// A role is an autonomous task: nobody is there to approve a change, so its access is full and not a choice.
    private var accessNote: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Copy.chatComposerAccess().uppercased()).scaledFont(11, weight: .semibold).tracking(0.6).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Label(Copy.chatPickerFullAccess(), icon: .lockOpen).labelStyle(.titleAndIcon).scaledFont(13, weight: .semibold).foregroundStyle(.orange)
            }
            Text(Copy.chatPickerFullAccessNote())
                .scaledFont(12).foregroundStyle(.primary.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, panelMargin).padding(.vertical, Tokens.Space.s14)
        .overlay(alignment: .top) { Divider() }
    }
}

