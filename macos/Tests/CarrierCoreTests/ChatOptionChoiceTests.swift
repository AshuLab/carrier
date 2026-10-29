import Testing

@testable import CarrierCore

@Test func aValueTheProviderGaveInLowerCaseStartsWithACapital() {
    #expect(choiceLabel(option: "effort", value: "low", label: "low") == "Low")
    #expect(choiceLabel(option: "effort", value: "xhigh", label: "xhigh") == "Extra high")
    #expect(choiceLabel(option: "model", value: "opus", label: "Opus") == "Opus")
    #expect(choiceLabel(option: "permissionMode", value: "default", label: "Ask before each change") == "Ask before each change")
}

@Test func theRowsCarryWhatTheProviderSaidOfAModelAndOurLineForTheSharedValues() {
    let options = [
        ChatOption(id: "model", label: "Model", values: [.init(id: "haiku", label: "Haiku", detail: "Fastest", version: "claude-haiku-5-5")], current: "haiku"),
        ChatOption(id: "effort", label: "Reasoning effort", values: [.init(id: "low", label: "low")], current: ""),
    ]
    let rows = optionRows(options)
    #expect(rows[0].choices[0].version == "claude-haiku-5-5")
    #expect(rows[0].choices[0].detail == "Fastest")
    #expect(rows[0].choices[0].icon == "cpu")
    #expect(rows[1].choices[0].label == "Low")
    #expect(rows[1].choices[0].detail != nil)
    #expect(rows[1].choices[0].icon == "gauge.with.dots.needle.0percent")
}
