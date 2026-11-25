import SwiftUI

/// A line a page puts at the right of its own header, only when there is something to say (why the Behavior page cannot save).
struct SettingsHeaderNote: Equatable {
    /// `plain`: a fact that is no one's fault, said quietly
    enum Tone { case problem, plain }
    let text: String
    let tone: Tone
    /// A problem is said to VoiceOver when it appears; one whose page says it itself (once, when the answer comes) leaves it to the page.
    var announces = true
    /// The engine did not apply the save: the note has a way to ask it again, without a new edit.
    var asksAgain = false
}

struct SettingsHeaderNoteKey: SwiftUI.PreferenceKey {
    static let defaultValue: SettingsHeaderNote? = nil
    static func reduce(value: inout SettingsHeaderNote?, nextValue: () -> SettingsHeaderNote?) { value = nextValue() ?? value }
}
