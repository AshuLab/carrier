import Foundation

// The right panel's tabs: which one opens, the choice that is remembered and the short count of each
// (docs/specs/macos-app-redesign.md, story 26). The views map them one to one.

public enum InspectorTab: String, CaseIterable {
    case slices, review, details

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// The tab the person picked, kept in user defaults so it holds for every epic and survives a relaunch.
public struct InspectorStore {
    private let defaults: UserDefaults
    private let key = "inspector.tab"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var chosen: InspectorTab? {
        get { defaults.string(forKey: key).flatMap(InspectorTab.init(rawValue:)) }
        nonmutating set { defaults.set(newValue?.rawValue, forKey: key) }
    }
}

/// The tab to show: the one the person chose, else Slices while the epic is running in ship and Review otherwise.
public func inspectorTab(_ subject: EpicSubject?, chosen: InspectorTab?) -> InspectorTab {
    if let chosen { return chosen }
    if case .active(let epic)? = subject, epic.status == .running, epic.stage == .ship { return .slices }
    return .review
}

public struct InspectorCount: Equatable {
    /// nil when there is nothing to count.
    public var text: String?
    /// The Review count is orange when the epic needs a person.
    public var needsYou = false
}

/// Slices merged over total, `R2` for the round, nothing for Details. The `epic` reply fills what the snapshot lacks.
public func inspectorCount(_ tab: InspectorTab, _ subject: EpicSubject?, reply: EpicReply? = nil) -> InspectorCount {
    var active: PanelEpic?
    if case .active(let epic)? = subject { active = epic }
    switch tab {
    case .slices:
        if let slices = active?.slices, slices.total > 0 { return InspectorCount(text: "\(slices.done)/\(slices.total)") }
        let all = reply?.slices ?? []
        return InspectorCount(text: all.isEmpty ? nil : "\(all.filter { $0.state == "closed" }.count)/\(all.count)")
    case .review:
        let round = active?.round ?? reply?.rounds.last?.round
        return InspectorCount(text: round.map { "R\($0)" }, needsYou: active?.status == .needsHuman)
    case .details:
        return InspectorCount(text: nil)
    }
}
