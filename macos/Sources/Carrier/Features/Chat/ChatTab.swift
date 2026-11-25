import CarrierCore
import SwiftUI

/// How the message box behaves (the key that sends and what the system does to the text) and what the conversation does and shows.
struct ChatTabView: View {
    @AppStorage(Preference.chatSendKey) private var sendKey
    @AppStorage(Preference.chatWhileWorking) private var whileWorking
    @AppStorage(Preference.chatWritingTools) private var writingTools
    @AppStorage(Preference.chatCheckSpelling) private var checksSpelling
    @AppStorage(Preference.chatCorrectSpelling) private var correctsSpelling
    @AppStorage(Preference.chatShowsContextUsage) private var showsContextUsage
    @AppStorage(Preference.chatFollowOutput) private var followsOutput
    @AppStorage(Preference.chatMessageTimes) private var messageTimes
    @AppStorage(Preference.chatToolOutput) private var toolOutput
    @AppStorage(Preference.chatOpensFailedCalls) private var opensFailedCalls
    @AppStorage(Preference.chatDiffStyle) private var diffStyle
    @AppStorage(Preference.chatOutputLength) private var outputLines
    @AppStorage(Preference.chatShowReasoning) private var showsReasoning
    @AppStorage(Preference.appearanceMessageWidth) private var messageWidth
    @AppStorage(Preference.chatSurface) private var chatSurface
    @AppStorage(Preference.chatTextSize) private var textSize
    @AppStorage(Preference.chatLineSpacing) private var lineSpacing
    @AppStorage(Preference.chatMessageSpacing) private var messageSpacing
    @State private var previewRoom: CGFloat = 0
    @State private var flipped: Set<String> = []

    /// The column of a conversation as the person set it, drawn with the feed's own rows (a message of theirs, the agent's work, its answer) in the
    /// middle of a track that is the widest column: the column is to the track as the chosen width is to the widest one, so the four differ in
    /// where the lines break and in how much of the track they take.
    private var messagePreview: some View {
        SettingsPreview {
            VStack(alignment: .leading, spacing: messageSpacing.gap) {
                ForEach(sampleConversation()) { row in
                    FeedRowView(
                        row: row, time: nil, summary: nil, pinned: false, flipped: $flipped, agent: "claude", commands: [], offersWayOut: false,
                        work: WorkState(live: false, waiting: false, since: nil)
                    )
                }
            }
            .padding(.vertical, 12)
            .frame(width: previewRoom * messageWidth.points / MessageWidth.widest.points, alignment: .leading)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { previewRoom = $0 }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.chat) }) {
            SettingsGroup(id: "message-box", title: "Message box") {
                SettingsTabRow(id: "send-with", title: "Send with", detail: "The other key makes a new line", first: true) {
                    ChoicePopUp(label: "Send with", options: [(value: SendKey.return, title: "Return"), (value: .commandReturn, title: "\u{2318}Return")], selection: $sendKey)
                }
                SettingsTabRow(id: "while-the-agent-works", title: "While the agent works", detail: "Hold the message, or stop the turn and send it") {
                    ChoicePopUp(label: "While the agent works", options: [(value: WhileWorking.queue, title: "Queue it"), (value: .interrupt, title: "Interrupt")], selection: $whileWorking)
                }
                SettingsTabRow(id: "writing-tools", title: "Writing Tools", detail: "The system's offer to rewrite or proofread what you select") {
                    Toggle("Writing Tools", isOn: $writingTools).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "check-spelling", title: "Check spelling", detail: "Underline words that look misspelled") {
                    Toggle("Check spelling", isOn: $checksSpelling).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "correct-spelling-automatically", title: "Correct spelling automatically", detail: "Fix a misspelled word as you type it") {
                    Toggle("Correct spelling automatically", isOn: $correctsSpelling).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "context-and-limits", title: "Context and limits", detail: "A ring beside the microphone: how full the context is and how much of the 5h limit is used") {
                    Toggle("Context and limits", isOn: $showsContextUsage).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "conversation", title: "Conversation") {
                SettingsTabRow(id: "follow-new-output", title: "Follow new output", detail: "Scroll to what arrives while you are at the end", first: true) {
                    Toggle("Follow new output", isOn: $followsOutput).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "message-times", title: "Message times", detail: "When a message shows the time it was written, as in General") {
                    ChoicePopUp(label: "Message times", options: MessageTimes.allCases.map { (value: $0, title: $0.title) }, selection: $messageTimes)
                }
                SettingsTabRow(id: "tool-output", title: "Tool output", detail: "Nothing, each run folded, or every call open") {
                    ChoicePopUp(label: "Tool output", options: ToolOutputMode.allCases.map { (value: $0, title: $0.title) }, selection: $toolOutput)
                }
                SettingsTabRow(id: "open-the-calls-that-failed", title: "Open the calls that failed", detail: "A call that failed opens by itself, even when the rest are folded") {
                    Toggle("Open the calls that failed", isOn: $opensFailedCalls).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "diff-style", title: "Diff style", detail: "Unified, or removed and added side by side") {
                    ChoicePopUp(label: "Diff style", options: DiffStyle.allCases.map { (value: $0, title: $0.title) }, selection: $diffStyle)
                }
                SettingsTabRow(id: "output-length", title: "Output length", detail: "How many lines of an output show before Show more") {
                    ChoicePopUp(label: "Output length", options: OutputLength.allCases.map { (value: $0, title: $0.title) }, selection: Binding(get: { OutputLength(rawValue: outputLines) ?? AppPreferences.defaultOutputLength }, set: { outputLines = $0.rawValue }))
                }
                SettingsTabRow(id: "show-reasoning", title: "Show reasoning", detail: "The agent's reasoning, folded under its message, when its host sends it") {
                    Toggle("Show reasoning", isOn: $showsReasoning).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "message-text-size", title: "Message text size", detail: "The size of the text of the messages, \(Int(textSize)) pt, apart from the text size of the app") {
                    Slider(value: $textSize, in: Double(ChatText.sizeRange.lowerBound)...Double(ChatText.sizeRange.upperBound), step: 1)
                        .labelsHidden().frame(width: settingsSliderWidth).accessibilityLabel("Message text size").accessibilityValue("\(Int(textSize)) points")
                }
                SettingsTabRow(id: "line-spacing", title: "Line spacing", detail: "The room between the lines of a message") {
                    ChoicePopUp(label: "Line spacing", options: ChatLineSpacing.allCases.map { (value: $0, title: $0.title) }, selection: $lineSpacing)
                }
                SettingsTabRow(id: "message-spacing", title: "Message spacing", detail: "The room between the messages") {
                    ChoicePopUp(label: "Message spacing", options: MessageSpacing.allCases.map { (value: $0, title: $0.title) }, selection: $messageSpacing)
                }
                SettingsTabRow(id: "message-width", title: "Message width", detail: "How wide a message gets before it wraps") {
                    ChoicePopUp(
                        label: "Message width", options: MessageWidth.allCases.map { (value: $0, title: "\($0.title) · \(Int($0.points)) pt") },
                        selection: $messageWidth
                    )
                }
                SettingsTabRow(id: "surfaces", title: "Surfaces", detail: "Glass blurs what is under; flat is a quiet solid fill") {
                    SegmentedChoice(options: ChatSurface.allCases.map { (value: $0, title: $0.title, icon: nil) }, selection: $chatSurface)
                }
                messagePreview
            }
        }
    }
}
