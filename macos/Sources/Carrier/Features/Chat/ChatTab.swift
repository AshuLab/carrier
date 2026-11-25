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
            .padding(.vertical, Tokens.Space.s12)
            .frame(width: previewRoom * messageWidth.points / MessageWidth.widest.points, alignment: .leading)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { previewRoom = $0 }
            .padding(Tokens.Space.s8)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.card).strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
    }

    var body: some View {
        SettingsPageBody(reset: { AppPreferences().reset(.chat) }) {
            SettingsGroup(id: "message-box", title: Copy.chatSettingsMessageBox()) {
                SettingsTabRow(id: "send-with", title: Copy.chatSettingsSendWith(), detail: Copy.chatSettingsSendWithDetail(), first: true) {
                    ChoicePopUp(label: Copy.chatSettingsSendWith(), options: [(value: SendKey.return, title: Copy.chatSettingsKeyReturn()), (value: .commandReturn, title: Copy.chatSettingsKeyCommandReturn())], selection: $sendKey)
                }
                SettingsTabRow(id: "while-the-agent-works", title: Copy.chatSettingsWhileWorking(), detail: Copy.chatSettingsWhileWorkingDetail()) {
                    ChoicePopUp(label: Copy.chatSettingsWhileWorking(), options: [(value: WhileWorking.queue, title: Copy.chatSettingsQueueIt()), (value: .interrupt, title: Copy.chatSettingsInterrupt())], selection: $whileWorking)
                }
                SettingsTabRow(id: "writing-tools", title: Copy.chatSettingsWritingTools(), detail: Copy.chatSettingsWritingToolsDetail()) {
                    Toggle(Copy.chatSettingsWritingTools(), isOn: $writingTools).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "check-spelling", title: Copy.chatSettingsCheckSpelling(), detail: Copy.chatSettingsCheckSpellingDetail()) {
                    Toggle(Copy.chatSettingsCheckSpelling(), isOn: $checksSpelling).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "correct-spelling-automatically", title: Copy.chatSettingsCorrectSpelling(), detail: Copy.chatSettingsCorrectSpellingDetail()) {
                    Toggle(Copy.chatSettingsCorrectSpelling(), isOn: $correctsSpelling).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "context-and-limits", title: Copy.chatSettingsContextAndLimits(), detail: Copy.chatSettingsContextAndLimitsDetail()) {
                    Toggle(Copy.chatSettingsContextAndLimits(), isOn: $showsContextUsage).labelsHidden().toggleStyle(.switch)
                }
            }
            SettingsGroup(id: "conversation", title: Copy.chatSettingsConversation()) {
                SettingsTabRow(id: "follow-new-output", title: Copy.chatSettingsFollowOutput(), detail: Copy.chatSettingsFollowOutputDetail(), first: true) {
                    Toggle(Copy.chatSettingsFollowOutput(), isOn: $followsOutput).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "message-times", title: Copy.chatSettingsMessageTimes(), detail: Copy.chatSettingsMessageTimesDetail()) {
                    ChoicePopUp(label: Copy.chatSettingsMessageTimes(), options: MessageTimes.allCases.map { (value: $0, title: $0.title()) }, selection: $messageTimes)
                }
                SettingsTabRow(id: "tool-output", title: Copy.chatSettingsToolOutput(), detail: Copy.chatSettingsToolOutputDetail()) {
                    ChoicePopUp(label: Copy.chatSettingsToolOutput(), options: ToolOutputMode.allCases.map { (value: $0, title: $0.title()) }, selection: $toolOutput)
                }
                SettingsTabRow(id: "open-the-calls-that-failed", title: Copy.chatSettingsOpenFailed(), detail: Copy.chatSettingsOpenFailedDetail()) {
                    Toggle(Copy.chatSettingsOpenFailed(), isOn: $opensFailedCalls).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "diff-style", title: Copy.chatSettingsDiffStyle(), detail: Copy.chatSettingsDiffStyleDetail()) {
                    ChoicePopUp(label: Copy.chatSettingsDiffStyle(), options: DiffStyle.allCases.map { (value: $0, title: $0.title()) }, selection: $diffStyle)
                }
                SettingsTabRow(id: "output-length", title: Copy.chatSettingsOutputLength(), detail: Copy.chatSettingsOutputLengthDetail()) {
                    ChoicePopUp(label: Copy.chatSettingsOutputLength(), options: OutputLength.allCases.map { (value: $0, title: $0.title()) }, selection: Binding(get: { OutputLength(rawValue: outputLines) ?? AppPreferences.defaultOutputLength }, set: { outputLines = $0.rawValue }))
                }
                SettingsTabRow(id: "show-reasoning", title: Copy.chatSettingsShowReasoning(), detail: Copy.chatSettingsShowReasoningDetail()) {
                    Toggle(Copy.chatSettingsShowReasoning(), isOn: $showsReasoning).labelsHidden().toggleStyle(.switch)
                }
                SettingsTabRow(id: "message-text-size", title: Copy.chatSettingsTextSize(), detail: Copy.chatSettingsTextSizeDetail(size: Int(textSize))) {
                    Slider(value: $textSize, in: Double(ChatText.sizeRange.lowerBound)...Double(ChatText.sizeRange.upperBound), step: 1)
                        .labelsHidden().frame(width: settingsSliderWidth).accessibilityLabel(Copy.chatSettingsTextSize()).accessibilityValue(Copy.chatSettingsTextSizeValue(size: Int(textSize)))
                }
                SettingsTabRow(id: "line-spacing", title: Copy.chatSettingsLineSpacing(), detail: Copy.chatSettingsLineSpacingDetail()) {
                    ChoicePopUp(label: Copy.chatSettingsLineSpacing(), options: ChatLineSpacing.allCases.map { (value: $0, title: $0.title()) }, selection: $lineSpacing)
                }
                SettingsTabRow(id: "message-spacing", title: Copy.chatSettingsMessageSpacing(), detail: Copy.chatSettingsMessageSpacingDetail()) {
                    ChoicePopUp(label: Copy.chatSettingsMessageSpacing(), options: MessageSpacing.allCases.map { (value: $0, title: $0.title()) }, selection: $messageSpacing)
                }
                SettingsTabRow(id: "message-width", title: Copy.chatSettingsMessageWidth(), detail: Copy.chatSettingsMessageWidthDetail()) {
                    ChoicePopUp(
                        label: Copy.chatSettingsMessageWidth(), options: MessageWidth.allCases.map { (value: $0, title: Copy.chatSettingsWidthOption(title: $0.title(), points: Int($0.points))) },
                        selection: $messageWidth
                    )
                }
                SettingsTabRow(id: "surfaces", title: Copy.chatSettingsSurfaces(), detail: Copy.chatSettingsSurfacesDetail()) {
                    SegmentedChoice(options: ChatSurface.allCases.map { (value: $0, title: $0.title(), icon: nil) }, selection: $chatSurface)
                }
                messagePreview
            }
        }
    }
}
