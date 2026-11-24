import Testing

@testable import CarrierCore

private func claude(model: String = "default", effort: String? = "medium", mode: String = "default") -> [ChatOption] {
    [
        ChatOption(id: "permissionMode", label: "Permission mode", values: ["default", "acceptEdits", "plan", "auto", "dontAsk"].map { .init(id: $0, label: $0) }, current: mode),
        ChatOption(id: "model", label: "Model", values: [.init(id: "default", label: "Default (recommended)"), .init(id: "opus", label: "Opus")], current: model),
    ] + (effort.map { [ChatOption(id: "effort", label: "Reasoning effort", values: ["low", "medium", "high", "xhigh"].map { .init(id: $0, label: $0) }, current: $0)] } ?? [])
}

@Test func theMenuHasTheModelsAReasoningScaleAndAnAccessScaleFromTheCarefulToTheFree() {
    let menu = composerMenu(claude())
    #expect(menu.models.map(\.id) == ["default", "opus"] && menu.pillModel == "Default")
    #expect(menu.reasoning?.steps.map(\.label) == ["Low", "Medium", "High", "Extra high"] && menu.pillReasoning == "Medium")
    #expect(menu.access.count == 1 && menu.access[0].title == "Access")
    #expect(menu.access[0].steps.map(\.id) == ["plan", "default", "acceptEdits", "auto", "dontAsk"] && menu.access[0].index == 1)
}

@Test func aModelWithNoEffortHasNoReasoningScale() {
    #expect(composerMenu(claude(effort: nil)).reasoning == nil && composerMenu(claude(effort: nil)).pillReasoning == nil)
}

@Test func thePillFlagsAnAccessFreerThanTheCarefulDefaultAndNeverAStricterOne() {
    #expect(composerMenu(claude()).accessFlag == nil)
    #expect(composerMenu(claude(mode: "auto")).accessFlag == "Auto")
    #expect(composerMenu(claude(mode: "plan")).accessFlag == nil)
}

@Test func anOptionWithTwoValuesIsASwitchWhoseOnIsTheFreerOne() {
    let menu = composerMenu([ChatOption(id: "sandbox", label: "Sandbox", values: [.init(id: "workspace-write", label: "Write in the folder"), .init(id: "read-only", label: "Read only")], current: "read-only")])
    #expect(menu.access[0].isSwitch && menu.access[0].steps.map(\.id) == ["read-only", "workspace-write"] && menu.access[0].index == 0)
    #expect(menu.access[0].current?.detail == "It can read the folder; it changes nothing." && menu.accessFlag == nil)
    #expect(composerMenu(claude()).access[0].isSwitch == false)
}

@Test func codexListsTwoScalesAndAnUnknownValueGoesLast() {
    let menu = composerMenu([
        ChatOption(id: "approvalPolicy", label: "Approval policy", values: ["never", "untrusted", "surprise"].map { .init(id: $0, label: $0) }, current: "untrusted"),
        ChatOption(id: "sandbox", label: "Sandbox", values: ["workspace-write", "read-only"].map { .init(id: $0, label: $0) }, current: "workspace-write"),
    ])
    #expect(menu.access.map(\.title) == ["Approval policy", "Sandbox"])
    #expect(menu.access[0].steps.map(\.id) == ["untrusted", "never", "surprise"] && menu.access[1].steps.map(\.id) == ["read-only", "workspace-write"])
    #expect(menu.access.map(\.isSwitch) == [false, true])
    #expect(menu.accessFlag == nil && menu.models.isEmpty)
}

@Test func nothingListedGivesAnEmptyMenu() {
    let menu = composerMenu([])
    #expect(menu.models.isEmpty && menu.reasoning == nil && menu.access.isEmpty && menu.pillModel == nil && menu.accessFlag == nil)
}
