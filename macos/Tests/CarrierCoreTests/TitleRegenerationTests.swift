import Foundation
import Testing
@testable import CarrierCore

private actor Sleeps {
    var asked: [Duration] = []
    func add(_ duration: Duration) { asked.append(duration) }
}

private func row(_ id: String, _ title: String) -> SessionRow {
    SessionRow(id: id, title: title, workspace: "w", agent: "claude", state: .idle, updatedAt: Date())
}

@MainActor @Test func aTitleWaitsAtLeastTheMinimumWhenTheModelAnswersAtOnceThenTheNewOneTakesItsPlace() async {
    let sleeps = Sleeps()
    let titles = TitleRegeneration(minimum: .seconds(2), keeps: .seconds(10), sleep: { await sleeps.add($0) })
    var seen: [Bool] = []
    let refusal = await titles.regenerate("a", showing: "Old title") {
        seen.append(titles.waiting.contains("a"))
        return ("A new title", nil)
    }
    #expect(refusal == nil && seen == [true])
    // it asked to wait for what was left of the two seconds, and the title it wrote is what the row says until the list catches up
    let waited = await sleeps.asked
    #expect(waited.first.map { $0 > .milliseconds(1500) && $0 <= .seconds(2) } == true)
    #expect(titles.waiting.isEmpty && titles.title(of: row("a", "Old title")) == "A new title")
    #expect(titles.title(of: row("b", "Another")) == "Another")
}

@MainActor @Test func aSlowModelIsWaitedForAndNotHeldLonger() async {
    let sleeps = Sleeps()
    // a call that takes longer than the minimum adds no wait of its own
    let titles = TitleRegeneration(minimum: .milliseconds(1), keeps: .seconds(10), sleep: { await sleeps.add($0) })
    _ = await titles.regenerate("a", showing: "Old title") {
        try? await Task.sleep(for: .milliseconds(30))
        return ("Slow", nil)
    }
    #expect(titles.title(of: row("a", "Old")) == "Slow")
    try? await Task.sleep(for: .milliseconds(60))
    #expect(await sleeps.asked == [.seconds(10)]) // only the hold of the new title, no wait of its own
}

@MainActor @Test func aRefusalStopsTheWaitKeepsTheOldTitleAndSaysWhy() async {
    let titles = TitleRegeneration(minimum: .milliseconds(1), keeps: .seconds(10), sleep: { _ in })
    let refusal = await titles.regenerate("a", showing: "Old title") { (nil, "No model can write it") }
    #expect(refusal == "No model can write it" && titles.waiting.isEmpty && titles.title(of: row("a", "Old")) == "Old")
}

@MainActor @Test func aSessionAlreadyWaitingIsLeftAlone() async {
    let titles = TitleRegeneration(minimum: .milliseconds(1), keeps: .seconds(10), sleep: { _ in })
    var inner: String?? = nil
    _ = await titles.regenerate("a", showing: "Old title") {
        inner = await titles.regenerate("a", showing: "Old title") { ("again", nil) }
        return ("first", nil)
    }
    #expect(inner == .some(nil) && titles.title(of: row("a", "Old")) == "first")
}

@MainActor @Test func theNewTitleIsLetGoOnceTheListHasHadTimeToCatchUp() async {
    let titles = TitleRegeneration(minimum: .milliseconds(1), keeps: .milliseconds(20), sleep: { try? await Task.sleep(for: $0) })
    _ = await titles.regenerate("a", showing: "Old title") { ("New", nil) }
    #expect(titles.title(of: row("a", "Old")) == "New")
    try? await Task.sleep(for: .milliseconds(120))
    #expect(titles.title(of: row("a", "Renamed by hand")) == "Renamed by hand")
}

@MainActor @Test func theOldTitleStaysUnderTheShimmerEvenWhenTheListBringsTheNewOneBeforeTheWaitEnds() async {
    let titles = TitleRegeneration(minimum: .milliseconds(1), keeps: .seconds(10), sleep: { _ in })
    var during: [String] = []
    _ = await titles.regenerate("a", showing: "Old title") {
        // the host answered and the list already has the new title while the wait goes on
        during.append(titles.title(of: row("a", "Old title")))
        during.append(titles.title(of: row("a", "Brand new title")))
        return ("Brand new title", nil)
    }
    #expect(during == ["Old title", "Old title"])
    #expect(titles.title(of: row("a", "Brand new title")) == "Brand new title")
}
