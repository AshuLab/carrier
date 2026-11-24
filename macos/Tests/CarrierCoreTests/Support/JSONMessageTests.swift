import Foundation
import Testing
@testable import CarrierCore

private let slice = """
{
  "slice": "#285",
  "outcome": "ready-to-merge",
  "branch": "feat/finished-epics-in-view/285-english-cancel-reasons",
  "pr": "https://github.com/AshuLab/carrier/pull/289",
  "definitionOfDone": {
    "pnpm typecheck passes": true,
    "pnpm test passes": false,
    "no Spanish cancel reason left": true
  },
  "note": "Changed engine.ts."
}
"""

@Test func aSliceReportBecomesACardWithTheUnfinishedChecksFirst() {
    guard case .slice(let report)? = jsonMessage(slice) else {
        Issue.record("a slice report is not a slice card")
        return
    }
    #expect(report.title == "Slice #285")
    #expect(report.outcome == "Ready to merge")
    #expect(report.tone == .good)
    #expect(report.pull == ReportLink(label: "PR #289", url: URL(string: "https://github.com/AshuLab/carrier/pull/289")!))
    #expect(report.branch == "feat/finished-epics-in-view/285-english-cancel-reasons")
    #expect(report.checks.map(\.name) == ["pnpm test passes", "pnpm typecheck passes", "no Spanish cancel reason left"])
    #expect(report.note == "Changed engine.ts.")
}

// The `ship` skill's template has bare keys and agents copy it: the same report, as JSON5.
@Test func aReportWithBareKeysAndANumberedSliceIsTheSameCard() {
    guard case .slice(let report)? = jsonMessage("""
    {slice:351, outcome:"ready-to-merge", branch:"feat/x/351-y", pr:"https://github.com/AshuLab/carrier/pull/356",
    definitionOfDone:{loadConfigRules:true, typecheck:false}, note:"Small."}
    """) else {
        Issue.record("a report with bare keys is not a slice card")
        return
    }
    #expect(report.title == "Slice #351")
    #expect(report.checks.map(\.name) == ["typecheck", "loadConfigRules"])
    #expect(report.note == "Small.")
}

@Test func theReportInACodeFenceIsTheSameReport() {
    #expect(jsonMessage("```json\n\(slice)\n```") == jsonMessage(slice))
}

@Test func anyOtherObjectIsALabelledListInTheOrderItWasWritten() {
    let message = jsonMessage("""
    {"repo": "AshuLab/carrier", "filesTouched": 7, "approved": false, "gone": null,
     "link": "https://github.com/AshuLab/carrier/pull/291", "checks": {"unit": true, "integration": false},
     "followUps": ["rename settle", "add a test"], "where": "src/engine.ts", "slice": "#1", "extra": 1}
    """)
    guard case .fields(let fields)? = message else {
        Issue.record("an object with other keys is not a list of fields")
        return
    }
    #expect(fields.map(\.label) == ["Repo", "Files touched", "Approved", "Link", "Checks", "Follow ups", "Where", "Slice", "Extra"])
    #expect(fields[0].value == .text("AshuLab/carrier") || fields[0].value == .code("AshuLab/carrier"))
    #expect(fields[1].value == .number("7"))
    #expect(fields[2].value == .flag(false))
    #expect(fields[3].value == .link(ReportLink(label: "AshuLab/carrier/pull/291", url: URL(string: "https://github.com/AshuLab/carrier/pull/291")!)))
    #expect(fields[4].value == .checks([ReportCheck(name: "integration", passed: false), ReportCheck(name: "unit", passed: true)]))
    #expect(fields[5].value == .list(["rename settle", "add a test"]))
    #expect(fields[6].value == .code("src/engine.ts"))
}

@Test func aSliceReportWithAnExtraKeyKeepsEveryKey() {
    guard case .fields(let fields)? = jsonMessage(#"{"outcome": "ready", "definitionOfDone": {"a": true}, "risk": "low"}"#) else {
        Issue.record("a report with a key the card does not know is not a list of fields")
        return
    }
    #expect(fields.map(\.label) == ["Outcome", "Definition of done", "Risk"])
}

@Test func whatIsNotAJSONObjectStaysText() {
    #expect(jsonMessage("Done. {\"a\": 1}") == nil)
    #expect(jsonMessage("{not json}") == nil)
    #expect(jsonMessage("{}") == nil)
    #expect(jsonMessage("[1, 2]") == nil)
    #expect(jsonMessage("```json\n{\"a\": 1}\n") == nil)
}
