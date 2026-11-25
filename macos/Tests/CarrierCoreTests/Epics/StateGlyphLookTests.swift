import Testing
@testable import CarrierCore

// What the glyph of an epic's state is made of, which the app draws with `StateGlyph`: the form, the color, the mark, the shape that stands for it when
// states are told apart by shape, and the words a screen reader says.

@Test func aRunningEpicIsARingAndAWaitingOneAHollowCircle() {
    #expect(EpicMenuState.running.glyphLook().form == .ring && EpicMenuState.running.glyphLook().shape == .working)
    let waiting = EpicMenuState.waiting.glyphLook()
    #expect(waiting.form == .hollow && waiting.tint == .gray && waiting.shape == nil && waiting.label == "Up next")
}

@Test func anEpicThatNeedsYouIsAnOrangeDiscAndRedWhenSomethingFailed() {
    let asks = EpicMenuState.needsYou.glyphLook(attention: .input)
    #expect(asks == StateGlyphLook(form: .disc, tint: .orange, mark: "!", shape: .needsAttention, label: "Needs attention"))
    let failed = EpicMenuState.needsYou.glyphLook(attention: .error)
    #expect(failed == StateGlyphLook(form: .disc, tint: .red, mark: "!", shape: .problem, label: "Needs attention"))
    // a kind the app does not know is a person's input
    #expect(EpicMenuState.needsYou.glyphLook() == asks)
}

@Test func aReadyEpicIsABlueDiscAndADoneOrCancelledOneHasNoShape() {
    #expect(EpicMenuState.ready.glyphLook() == StateGlyphLook(form: .disc, tint: .blue, mark: "✓", shape: .ready, label: "Ready for test"))
    #expect(EpicMenuState.done.glyphLook() == StateGlyphLook(form: .disc, tint: .green, mark: "✓", shape: nil, label: "Done"))
    #expect(EpicMenuState.cancelled.glyphLook() == StateGlyphLook(form: .disc, tint: .gray, mark: "✕", shape: nil, label: "Cancelled"))
}
