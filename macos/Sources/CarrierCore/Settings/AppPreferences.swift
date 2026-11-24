import Foundation

/// The App group's preferences, kept in user defaults so they hold across a relaunch: each with its default, and a bad saved value
/// reads as the default. The keys are the ones that already existed, so nothing a person set is lost.
public struct AppPreferences {
    public static let styleKey = Preference.menuIconStyle.name
    public static let animatesKey = Preference.menuAnimate.name
    public static let confirmStopKey = Preference.stopConfirm.name
    public static let timeStyleKey = Preference.displayTimeStyle.name
    public static let clockHoursKey = Preference.displayClock.name
    public static let colorSchemeKey = Preference.appearanceColorScheme.name
    public static let densityKey = Preference.appearanceDensity.name
    public static let themeKey = Preference.appearanceTheme.name
    public static let accentKey = Preference.appearanceAccent.name
    public static let tintKey = Preference.appearanceTint.name
    public static let translucentKey = Preference.appearanceTranslucent.name
    public static let monospaceFamilyKey = Preference.appearanceMonoFamily.name
    public static let monospaceSizeKey = Preference.appearanceMonoSize.name
    public static let monospaceLineHeightKey = Preference.appearanceMonoLineHeight.name
    public static let monospaceLigaturesKey = Preference.appearanceMonoLigatures.name
    public static let monospaceWrapKey = Preference.appearanceMonoWrap.name
    public static let monospaceLineNumbersKey = Preference.appearanceMonoLineNumbers.name
    public static let statesByShapeKey = Preference.appearanceStatesByShape.name
    public static let messageWidthKey = Preference.appearanceMessageWidth.name
    public static let chatTextSizeKey = Preference.chatTextSize.name
    public static let chatLineSpacingKey = Preference.chatLineSpacing.name
    public static let chatMessageSpacingKey = Preference.chatMessageSpacing.name
    public static let chatSurfaceKey = Preference.chatSurface.name
    public static let sendKeyKey = Preference.chatSendKey.name
    public static let whileWorkingKey = Preference.chatWhileWorking.name
    public static let writingToolsKey = Preference.chatWritingTools.name
    public static let checksSpellingKey = Preference.chatCheckSpelling.name
    public static let correctsSpellingKey = Preference.chatCorrectSpelling.name
    public static let showsContextUsageKey = Preference.chatShowsContextUsage.name
    public static let followsOutputKey = Preference.chatFollowOutput.name
    public static let messageTimesKey = Preference.chatMessageTimes.name
    public static let toolOutputKey = Preference.chatToolOutput.name
    public static let opensFailedCallsKey = Preference.chatOpensFailedCalls.name
    public static let diffStyleKey = Preference.chatDiffStyle.name
    public static let outputLengthKey = Preference.chatOutputLength.name
    public static let confirmDeleteKey = Preference.chatConfirmDelete.name
    public static let showsReasoningKey = Preference.chatShowReasoning.name
    public static let newSessionAgentKey = Preference.chatNewSessionAgent.name
    public static let newSessionModelKey = Preference.chatNewSessionModel.name
    public static let newSessionEffortKey = Preference.chatNewSessionEffort.name
    public static let newSessionAccessKey = Preference.chatNewSessionAccess.name
    public static let workInKey = Preference.chatNewSessionWorkIn.name
    public static let dictationEnabledKey = Preference.dictationEnabled.name
    public static let dictationCleanupEnabledKey = Preference.dictationCleanupEnabled.name
    public static let dictationCleanupServerKey = Preference.dictationCleanupServer.name
    public static let dictationCleanupModelKey = Preference.dictationCleanupModel.name
    public static let dictationCleanupPromptKey = Preference.dictationCleanupPrompt.name
    public static let dictationModelKey = Preference.dictationModel.name
    /// Load the chosen model when Carrier opens with Dictation on, and when Dictation is turned on or the model or language changes.
    public static let dictationKeepReadyKey = Preference.dictationModelKeepReady.name
    /// Minutes without dictating after which the model is released; 0 is Never.
    public static let dictationReleaseAfterKey = Preference.dictationModelReleaseAfter.name
    public static let dictationLanguageKey = Preference.dictationLanguage.name
    public static let dictationGlobalKey = Preference.dictationGlobal.name
    public static let dictationKeepTextKey = Preference.dictationHistoryKeepText.name
    public static let dictationKeepAudioKey = Preference.dictationHistoryKeepAudio.name
    public static let dictationDeleteAudioAfterKey = Preference.dictationHistoryDeleteAudioAfter.name
    public static let dictationTypingSpeedKey = Preference.dictationStatisticsWpm.name
    public static let dictationAccessibilityExplainedKey = Preference.dictationAccessibilityExplained.name
    public static let dictationShortcutKey = Preference.dictationShortcut.name
    public static let dictationActivationKey = Preference.dictationActivation.name
    public static let dictationWidgetStyleKey = Preference.dictationWidgetStyle.name
    public static let dictationWidgetPositionKey = Preference.dictationWidgetPosition.name
    public static let dictationWidgetThemeKey = Preference.dictationWidgetTheme.name
    public static let dictationWidgetPreviewKey = Preference.dictationWidgetPreview.name
    public static let dictationWidgetSpotKey = Preference.dictationWidgetSpot.name
    public static let dictationStartSoundOnKey = Preference.dictationSoundStartOn.name
    public static let dictationStartSoundKey = Preference.dictationSoundStart.name
    public static let dictationEndSoundOnKey = Preference.dictationSoundEndOn.name
    public static let dictationEndSoundKey = Preference.dictationSoundEnd.name
    public static let dictationSoundVolumeKey = Preference.dictationSoundVolume.name
    public static let awakeScreenKey = Preference.awakeScreen.name
    public static let awakeMinutesKey = Preference.awakeMinutes.name
    public static let awakeAgentsKey = Preference.awakeAgents.name
    public static let awakeGraceKey = Preference.awakeGrace.name
    public static let awakeBatteryKey = Preference.awakeBattery.name
    public static let awakeNotifyKey = Preference.awakeNotify.name
    public static let awakeShortcutKey = Preference.awakeShortcut.name
    public static let updateDelayKey = Preference.updatesDelayDays.name
    public static let terminalThemeKey = Preference.terminalTheme.name
    public static let terminalFontFamilyKey = Preference.terminalFontFamily.name
    public static let terminalFontSizeKey = Preference.terminalFontSize.name
    public static let terminalFontLigaturesKey = Preference.terminalFontLigatures.name
    public static let terminalCursorStyleKey = Preference.terminalCursorStyle.name
    public static let terminalCursorBlinkKey = Preference.terminalCursorBlink.name
    public static let terminalPaddingXKey = Preference.terminalPaddingX.name
    public static let terminalPaddingYKey = Preference.terminalPaddingY.name
    public static let terminalMinimumContrastKey = Preference.terminalMinimumContrast.name
    public static let terminalConfirmCloseKey = Preference.terminalConfirmCloseRunningProcess.name
    public static let terminalPinPromptToBottomKey = Preference.terminalPinPromptToBottom.name
    public static let terminalDrawerHeightKey = Preference.terminalDrawerHeight.name
    public static let defaultTerminalDrawerHeight = Preference.terminalDrawerHeight.defaultValue
    public static let terminalFontThickenKey = Preference.terminalFontThicken.name
    public static let terminalDimInactivePanesKey = Preference.terminalPanesDimInactive.name
    public static let terminalFocusFollowsMouseKey = Preference.terminalPanesFocusFollowsMouse.name
    public static let terminalOptionAsAltKey = Preference.terminalInputOptionAsAlt.name
    public static let terminalCopyOnSelectKey = Preference.terminalInputCopyOnSelect.name
    public static let terminalScrollbackLimitKey = Preference.terminalScrollbackLimit.name

    public static let defaultStyle = Preference.menuIconStyle.defaultValue
    public static let defaultAnimates = Preference.menuAnimate.defaultValue
    public static let defaultShowsEpics = Preference.menuShowEpics.defaultValue
    public static let defaultConfirmStop = Preference.stopConfirm.defaultValue
    public static let defaultColorScheme = Preference.appearanceColorScheme.defaultValue
    public static let defaultDensity = Preference.appearanceDensity.defaultValue
    public static let defaultMessageWidth = Preference.appearanceMessageWidth.defaultValue
    public static let defaultChatLineSpacing = Preference.chatLineSpacing.defaultValue
    public static let defaultChatMessageSpacing = Preference.chatMessageSpacing.defaultValue
    public static let defaultChatSurface = Preference.chatSurface.defaultValue
    public static let defaultTheme = Preference.appearanceTheme.defaultValue
    public static let defaultTint = Preference.appearanceTint.defaultValue
    public static let defaultSendKey = Preference.chatSendKey.defaultValue
    public static let defaultWhileWorking = Preference.chatWhileWorking.defaultValue
    public static let defaultWritingTools = Preference.chatWritingTools.defaultValue
    public static let defaultChecksSpelling = Preference.chatCheckSpelling.defaultValue
    public static let defaultCorrectsSpelling = Preference.chatCorrectSpelling.defaultValue
    public static let defaultShowsContextUsage = Preference.chatShowsContextUsage.defaultValue
    public static let defaultFollowsOutput = Preference.chatFollowOutput.defaultValue
    public static let defaultMessageTimes = Preference.chatMessageTimes.defaultValue
    public static let defaultToolOutput = Preference.chatToolOutput.defaultValue
    public static let defaultOpensFailedCalls = Preference.chatOpensFailedCalls.defaultValue
    public static let defaultDiffStyle = Preference.chatDiffStyle.defaultValue
    public static let defaultOutputLength = OutputLength(rawValue: Preference.chatOutputLength.defaultValue) ?? .short
    public static let defaultConfirmDelete = Preference.chatConfirmDelete.defaultValue
    public static let defaultWorkIn = Preference.chatNewSessionWorkIn.defaultValue
    public static let defaultShowsReasoning = Preference.chatShowReasoning.defaultValue
    public static let defaultDictationEnabled = Preference.dictationEnabled.defaultValue
    public static let defaultDictationGlobal = Preference.dictationGlobal.defaultValue
    public static let defaultDictationKeepReady = Preference.dictationModelKeepReady.defaultValue
    public static let defaultDictationReleaseAfter = Preference.dictationModelReleaseAfter.defaultValue
    public static let defaultDictationKeepText = Preference.dictationHistoryKeepText.defaultValue
    public static let defaultDictationKeepAudio = Preference.dictationHistoryKeepAudio.defaultValue
    public static let defaultDictationDeleteAudioAfter = Preference.dictationHistoryDeleteAudioAfter.defaultValue
    public static let defaultDictationTypingSpeed = Preference.dictationStatisticsWpm.defaultValue
    public static let dictationTypingSpeedRange = 10...200
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// What a preference holds: the saved value, or its default while none is saved or the saved one is not valid.
    public func value<V: PreferenceValue>(_ key: PreferenceKey<V>) -> V { V.read(defaults, key.name) ?? key.defaultValue }

    public func store<V: PreferenceValue>(_ value: V, for key: PreferenceKey<V>) { value.write(defaults, key.name) }

    /// What an optional preference holds: nil while none is saved or the saved one is not valid.
    public func value<V: PreferenceValue>(_ key: OptionalPreferenceKey<V>) -> V? { V.read(defaults, key.name) }

    /// Keeps the value of an optional preference, or takes it out for nil (`@AppStorage` has no optional `Double`).
    public func store<V: PreferenceValue>(_ value: V?, for key: OptionalPreferenceKey<V>) {
        if let value { value.write(defaults, key.name) } else { defaults.removeObject(forKey: key.name) }
    }

    /// What a new session opens with: the provider, its model and its reasoning. Each is empty when the person chose none, and the session
    /// then takes the first provider that can work and that provider's own model and level.
    public var newSessionStart: NewSessionStart {
        NewSessionStart(
            agent: value(Preference.chatNewSessionAgent),
            model: value(Preference.chatNewSessionModel),
            effort: value(Preference.chatNewSessionEffort),
            access: NewSessionStart.access(fromJSON: value(Preference.chatNewSessionAccess))
        )
    }

    public var style: IconStyle {
        get { value(Preference.menuIconStyle) }
        nonmutating set { store(newValue, for: Preference.menuIconStyle) }
    }

    public var animates: Bool {
        get { value(Preference.menuAnimate) }
        nonmutating set { store(newValue, for: Preference.menuAnimate) }
    }

    public var showsEpics: Bool {
        get { value(Preference.menuShowEpics) }
        nonmutating set { store(newValue, for: Preference.menuShowEpics) }
    }

    /// Whether stopping Carrier asks first when it would interrupt epics.
    public var confirmStop: Bool {
        get { value(Preference.stopConfirm) }
        nonmutating set { store(newValue, for: Preference.stopConfirm) }
    }

    /// How ages and times read everywhere in the app: relative or as a clock time.
    public var timeStyle: TimeStyle {
        get { value(Preference.displayTimeStyle) }
        nonmutating set { store(newValue, for: Preference.displayTimeStyle) }
    }

    /// The clock of clock times: the Mac's, 12 or 24 hours.
    public var clockHours: ClockHours {
        get { value(Preference.displayClock) }
        nonmutating set { store(newValue, for: Preference.displayClock) }
    }

    /// The appearance of every window of the app: the Mac's, or light or dark whatever the Mac is.
    public var colorScheme: ColorSchemeChoice {
        get { value(Preference.appearanceColorScheme) }
        nonmutating set { store(newValue, for: Preference.appearanceColorScheme) }
    }

    /// The text size of the whole interface in percent, the one the type scale reads.
    public var textSize: Int {
        get { TypeScale.stored(in: defaults).percent }
        nonmutating set { store(TypeScale(percent: newValue).percent, for: Preference.appearanceTextSize) }
    }

    public var density: Density {
        get { value(Preference.appearanceDensity) }
        nonmutating set { store(newValue, for: Preference.appearanceDensity) }
    }

    public var theme: Theme {
        get { value(Preference.appearanceTheme) }
        nonmutating set { store(newValue, for: Preference.appearanceTheme) }
    }

    /// The accent the person picked; nil is the theme's own.
    public var accent: AccentColor? {
        get { value(Preference.appearanceAccent).flatMap(AccentColor.init(rawValue:)) }
        nonmutating set { store(newValue?.rawValue, for: Preference.appearanceAccent) }
    }

    public var tint: Tint {
        get { value(Preference.appearanceTint) }
        nonmutating set { store(newValue, for: Preference.appearanceTint) }
    }

    /// Whether windows are translucent: what the person chose, and while they did not, the opposite of the system's Reduce transparency.
    public func translucent(systemReducesTransparency: Bool) -> Bool {
        value(Preference.appearanceTranslucent) ?? (systemReducesTransparency == false)
    }

    public func setTranslucent(_ value: Bool) { store(value, for: Preference.appearanceTranslucent) }

    /// The font, size, line height, ligatures, wrapping and line numbers of code and output; a bad saved value reads as its default.
    public var monospace: MonospaceSettings {
        get {
            let size = CGFloat(value(Preference.appearanceMonoSize))
            return MonospaceSettings(
                family: value(Preference.appearanceMonoFamily),
                size: min(max(size, MonospaceSettings.sizeRange.lowerBound), MonospaceSettings.sizeRange.upperBound),
                lineHeight: value(Preference.appearanceMonoLineHeight),
                ligatures: value(Preference.appearanceMonoLigatures),
                wrapLongLines: value(Preference.appearanceMonoWrap),
                lineNumbers: value(Preference.appearanceMonoLineNumbers)
            )
        }
        nonmutating set {
            store(newValue.family, for: Preference.appearanceMonoFamily)
            store(Double(newValue.size), for: Preference.appearanceMonoSize)
            store(newValue.lineHeight, for: Preference.appearanceMonoLineHeight)
            store(newValue.ligatures, for: Preference.appearanceMonoLigatures)
            store(newValue.wrapLongLines, for: Preference.appearanceMonoWrap)
            store(newValue.lineNumbers, for: Preference.appearanceMonoLineNumbers)
        }
    }

    /// Whether each state wears a symbol beside its color, so that color is not the only clue.
    public var statesByShape: Bool {
        get { value(Preference.appearanceStatesByShape) }
        nonmutating set { store(newValue, for: Preference.appearanceStatesByShape) }
    }

    /// How wide a conversation gets before its messages wrap.
    public var messageWidth: MessageWidth {
        get { value(Preference.appearanceMessageWidth) }
        nonmutating set { store(newValue, for: Preference.appearanceMessageWidth) }
    }

    /// The size of the text of the messages, in points: the chat's own, apart from the text size of the app.
    public var chatTextSize: CGFloat {
        get { ChatText.clamped(CGFloat(value(Preference.chatTextSize))) }
        nonmutating set { store(Double(ChatText.clamped(newValue)), for: Preference.chatTextSize) }
    }

    /// The room between the lines of a message.
    public var chatLineSpacing: ChatLineSpacing {
        get { value(Preference.chatLineSpacing) }
        nonmutating set { store(newValue, for: Preference.chatLineSpacing) }
    }

    /// The room between the messages of a conversation.
    public var chatMessageSpacing: MessageSpacing {
        get { value(Preference.chatMessageSpacing) }
        nonmutating set { store(newValue, for: Preference.chatMessageSpacing) }
    }

    /// How the conversation draws its cards, bubbles and box: glass, or flat.
    public var chatSurface: ChatSurface {
        get { value(Preference.chatSurface) }
        nonmutating set { store(newValue, for: Preference.chatSurface) }
    }

    /// The key that sends in the message box; the other one makes a new line.
    public var sendKey: SendKey {
        get { value(Preference.chatSendKey) }
        nonmutating set { store(newValue, for: Preference.chatSendKey) }
    }

    /// What sending does while the agent answers.
    public var whileWorking: WhileWorking {
        get { value(Preference.chatWhileWorking) }
        nonmutating set { store(newValue, for: Preference.chatWhileWorking) }
    }

    /// Whether the system's Writing Tools offer to rewrite the text of the message box.
    public var writingTools: Bool {
        get { value(Preference.chatWritingTools) }
        nonmutating set { store(newValue, for: Preference.chatWritingTools) }
    }

    public var checksSpelling: Bool {
        get { value(Preference.chatCheckSpelling) }
        nonmutating set { store(newValue, for: Preference.chatCheckSpelling) }
    }

    public var correctsSpelling: Bool {
        get { value(Preference.chatCorrectSpelling) }
        nonmutating set { store(newValue, for: Preference.chatCorrectSpelling) }
    }

    /// Whether an open session's message box shows the ring of the context and the limits beside the microphone.
    public var showsContextUsage: Bool {
        get { value(Preference.chatShowsContextUsage) }
        nonmutating set { store(newValue, for: Preference.chatShowsContextUsage) }
    }

    /// Whether a conversation scrolls to new output while the person is at its end.
    public var followsOutput: Bool {
        get { value(Preference.chatFollowOutput) }
        nonmutating set { store(newValue, for: Preference.chatFollowOutput) }
    }

    /// Whether messages show the time they were written, written in the General format.
    public var messageTimes: MessageTimes {
        get { value(Preference.chatMessageTimes) }
        nonmutating set { store(newValue, for: Preference.chatMessageTimes) }
    }

    /// What the agent's tools show in a conversation.
    public var toolOutput: ToolOutputMode {
        get { value(Preference.chatToolOutput) }
        nonmutating set { store(newValue, for: Preference.chatToolOutput) }
    }

    /// Whether a call that failed opens by itself, whatever the mode but hidden.
    public var opensFailedCalls: Bool {
        get { value(Preference.chatOpensFailedCalls) }
        nonmutating set { store(newValue, for: Preference.chatOpensFailedCalls) }
    }

    /// How an edit's diff reads: its lines one under the other, or removed and added side by side.
    public var diffStyle: DiffStyle {
        get { value(Preference.chatDiffStyle) }
        nonmutating set { store(newValue, for: Preference.chatDiffStyle) }
    }

    /// How many lines of an output show before Show more.
    public var outputLength: OutputLength {
        get { OutputLength(rawValue: value(Preference.chatOutputLength)) ?? Self.defaultOutputLength }
        nonmutating set { store(newValue.rawValue, for: Preference.chatOutputLength) }
    }

    /// Whether the agent's reasoning shows folded under its message, when the host sends it.
    public var showsReasoning: Bool {
        get { value(Preference.chatShowReasoning) }
        nonmutating set { store(newValue, for: Preference.chatShowReasoning) }
    }

    /// Whether deleting a session asks first.
    public var confirmDelete: Bool {
        get { value(Preference.chatConfirmDelete) }
        nonmutating set { store(newValue, for: Preference.chatConfirmDelete) }
    }

    /// Where a new session opens: the base folder, or a new worktree when its folder offers one.
    public var workIn: WorkIn {
        get { value(Preference.chatNewSessionWorkIn) }
        nonmutating set { store(newValue, for: Preference.chatNewSessionWorkIn) }
    }

    /// The days the app waits after a release before it offers it by itself; none until the person chooses.
    public var updateDelayDays: Int {
        get { clampedUpdateDelay(value(Preference.updatesDelayDays)) }
        nonmutating set { store(clampedUpdateDelay(newValue), for: Preference.updatesDelayDays) }
    }

    /// Whether the message box has a microphone: Dictation is on until the person turns it off.
    public var dictationEnabled: Bool {
        get { value(Preference.dictationEnabled) }
        nonmutating set { store(newValue, for: Preference.dictationEnabled) }
    }

    /// Whether Cleanup is on: off until the person turns it on. It does not wait for a server and a model: the run needs them (`DictationController`).
    public var dictationCleanupEnabled: Bool {
        get { value(Preference.dictationCleanupEnabled) }
        nonmutating set { store(newValue, for: Preference.dictationCleanupEnabled) }
    }

    /// The model server Cleanup uses; nil while the person chose none.
    public var dictationCleanupServer: CleanupServer? {
        get { value(Preference.dictationCleanupServer) }
        nonmutating set { store(newValue, for: Preference.dictationCleanupServer) }
    }

    /// The model of that server Cleanup uses; nil while the person chose none.
    public var dictationCleanupModel: String? {
        get { value(Preference.dictationCleanupModel) }
        nonmutating set { store(newValue, for: Preference.dictationCleanupModel) }
    }

    /// The prompt of Cleanup: the default until the person writes one, and what they left (an empty box too) after.
    public var dictationCleanupPrompt: String {
        get { value(Preference.dictationCleanupPrompt) }
        nonmutating set { store(newValue, for: Preference.dictationCleanupPrompt) }
    }

    /// The id of the speech model the person chose; nil while they did not.
    public var dictationModelID: String? {
        get { value(Preference.dictationModel) }
        nonmutating set { store(newValue, for: Preference.dictationModel) }
    }

    /// The chosen speech model among those on offer: Apple's when none was chosen or the saved one is not on offer any more.
    public func dictationModel(among models: [SpeechModel]) -> SpeechModel? {
        models.first { $0.id == dictationModelID } ?? models.first { $0.recognizer == .apple }
    }

    /// The language the person chose, `automaticLanguage` or a base code; nil while they did not (`languageChoices` says what that is).
    public var dictationLanguage: String? {
        get { value(Preference.dictationLanguage) }
        nonmutating set { store(newValue, for: Preference.dictationLanguage) }
    }

    /// Whether the chosen speech model is loaded before the first dictation: on until the person turns it off.
    public var dictationKeepReady: Bool {
        get { value(Preference.dictationModelKeepReady) }
        nonmutating set { store(newValue, for: Preference.dictationModelKeepReady) }
    }

    /// The minutes without dictating after which the model is released (a choice of `dictationReleaseChoices`, 0 is never); a saved value that is not on offer reads as 15.
    public var dictationReleaseAfter: Int {
        get {
            let saved = value(Preference.dictationModelReleaseAfter)
            return dictationReleaseChoices.contains { $0.minutes == saved } ? saved : Self.defaultDictationReleaseAfter
        }
        nonmutating set { store(newValue, for: Preference.dictationModelReleaseAfter) }
    }

    /// Whether the history keeps the text of each dictation: on until the person turns it off. The entries that exist stay when it is off, and Reset never deletes them.
    public var dictationKeepText: Bool {
        get { value(Preference.dictationHistoryKeepText) }
        nonmutating set { store(newValue, for: Preference.dictationHistoryKeepText) }
    }

    /// Whether the history keeps the audio of each dictation it records: off until the person turns it on.
    public var dictationKeepAudio: Bool {
        get { value(Preference.dictationHistoryKeepAudio) }
        nonmutating set { store(newValue, for: Preference.dictationHistoryKeepAudio) }
    }

    /// The days after which the audio of a dictation is deleted (a choice of `dictationAudioLimits`, 0 is never); a saved value that is not on offer reads as 30.
    public var dictationDeleteAudioAfter: Int {
        get {
            let saved = value(Preference.dictationHistoryDeleteAudioAfter)
            return dictationAudioLimits.contains { $0.days == saved } ? saved : Self.defaultDictationDeleteAudioAfter
        }
        nonmutating set { store(newValue, for: Preference.dictationHistoryDeleteAudioAfter) }
    }

    /// How fast the person types, in words a minute, which the time saved is measured against: 40 until they set it, always within 10 to 200.
    public var dictationTypingSpeed: Int {
        get { min(max(value(Preference.dictationStatisticsWpm), Self.dictationTypingSpeedRange.lowerBound), Self.dictationTypingSpeedRange.upperBound) }
        nonmutating set { store(newValue, for: Preference.dictationStatisticsWpm) }
    }

    /// Whether the global shortcut dictates in any app: on until the person turns it off. It only counts while `dictationEnabled` is on too (`globalDictationIsOn`).
    public var dictationGlobal: Bool {
        get { value(Preference.dictationGlobal) }
        nonmutating set { store(newValue, for: Preference.dictationGlobal) }
    }

    /// Whether the page already told the person what Accessibility is for. Not a setting: Reset leaves it, so the explanation is not given twice.
    public var dictationAccessibilityExplained: Bool {
        get { value(Preference.dictationAccessibilityExplained) }
        nonmutating set { store(newValue, for: Preference.dictationAccessibilityExplained) }
    }

    /// The keys of the global dictation: ⌥⇧ Space until the person records another, and one that does not pass the recorder's rules reads as that.
    public var dictationShortcut: DictationShortcut {
        get { DictationShortcut(stored: value(Preference.dictationShortcut)) ?? .standard }
        nonmutating set { store(newValue.stored, for: Preference.dictationShortcut) }
    }

    /// What the Keep awake page sets; a missing or bad value reads as its default.
    public var awake: AwakeSettings {
        var settings = AwakeSettings()
        settings.keepsScreenOn = value(Preference.awakeScreen)
        settings.defaultMinutes = AwakeLength.valid(value(Preference.awakeMinutes))
        settings.followsAgents = value(Preference.awakeAgents)
        let grace = value(Preference.awakeGrace)
        if AwakeSettings.graceChoices.contains(grace) { settings.graceMinutes = grace }
        settings.battery = value(Preference.awakeBattery)
        settings.notifies = value(Preference.awakeNotify)
        return settings
    }

    /// The keys that turn Keep awake on or off from any app: none until the person records them, so no installed app loses a combination.
    public var awakeShortcut: DictationShortcut? {
        get { value(Preference.awakeShortcut).flatMap(DictationShortcut.init(stored:)) }
        nonmutating set { store(newValue?.stored, for: Preference.awakeShortcut) }
    }

    /// Toggle until the person chooses Hold.
    public var dictationActivation: DictationActivation {
        get { value(Preference.dictationActivation) }
        nonmutating set { store(newValue, for: Preference.dictationActivation) }
    }

    /// Medium until the person chooses another.
    public var dictationWidgetStyle: DictationWidgetStyle {
        get { value(Preference.dictationWidgetStyle) }
        nonmutating set { store(newValue, for: Preference.dictationWidgetStyle) }
    }

    /// Bottom until the person chooses Top.
    public var dictationWidgetPosition: DictationWidgetPosition {
        get { value(Preference.dictationWidgetPosition) }
        nonmutating set { store(newValue, for: Preference.dictationWidgetPosition) }
    }

    /// The widget's theme: the accent's glass until the person chooses another.
    public var dictationWidgetTheme: DictationWidgetTheme {
        get { value(Preference.dictationWidgetTheme) }
        nonmutating set { store(newValue, for: Preference.dictationWidgetTheme) }
    }

    /// Whether the widget shows the words as they are said; on until the person turns it off.
    public var dictationWidgetPreview: Bool {
        get { value(Preference.dictationWidgetPreview) }
        nonmutating set { store(newValue, for: Preference.dictationWidgetPreview) }
    }

    /// Where the person dragged the widget; nil until they do, and again when they choose Top or Bottom. A stored value that cannot be read is nil.
    public var dictationWidgetSpot: DictationWidgetSpot? {
        get { value(Preference.dictationWidgetSpot).flatMap(DictationWidgetSpot.init(text:)) }
        nonmutating set { store(newValue?.text, for: Preference.dictationWidgetSpot) }
    }

    /// The Sounds group of the Dictation page; a saved sound that is not on offer reads as the default, and the volume as 0 to 100.
    public var dictationSounds: DictationSounds {
        get {
            var sounds = DictationSounds()
            sounds.startOn = value(Preference.dictationSoundStartOn)
            sounds.endOn = value(Preference.dictationSoundEndOn)
            let start = value(Preference.dictationSoundStart), end = value(Preference.dictationSoundEnd)
            if dictationSoundChoices.contains(start) { sounds.start = start }
            if dictationSoundChoices.contains(end) { sounds.end = end }
            sounds.volume = min(max(value(Preference.dictationSoundVolume), DictationSounds.volumeRange.lowerBound), DictationSounds.volumeRange.upperBound)
            return sounds
        }
        nonmutating set {
            store(newValue.startOn, for: Preference.dictationSoundStartOn)
            store(newValue.start, for: Preference.dictationSoundStart)
            store(newValue.endOn, for: Preference.dictationSoundEndOn)
            store(newValue.end, for: Preference.dictationSoundEnd)
            store(newValue.volume, for: Preference.dictationSoundVolume)
        }
    }

    /// Settings for the embedded terminal (theme override, font overrides, cursor, padding, contrast, panes, input, scrollback, close confirmation).
    public var terminal: TerminalSettings {
        get {
            TerminalSettings(
                themeOverride: value(Preference.terminalTheme),
                fontFamilyOverride: value(Preference.terminalFontFamily),
                fontSizeOverride: value(Preference.terminalFontSize),
                fontLigaturesOverride: value(Preference.terminalFontLigatures),
                fontThicken: value(Preference.terminalFontThicken),
                cursorStyle: value(Preference.terminalCursorStyle),
                cursorBlink: value(Preference.terminalCursorBlink),
                paddingX: value(Preference.terminalPaddingX),
                paddingY: value(Preference.terminalPaddingY),
                minimumContrast: value(Preference.terminalMinimumContrast),
                dimInactivePanes: value(Preference.terminalPanesDimInactive),
                focusFollowsMouse: value(Preference.terminalPanesFocusFollowsMouse),
                optionAsAlt: value(Preference.terminalInputOptionAsAlt),
                copyOnSelect: value(Preference.terminalInputCopyOnSelect),
                scrollbackLimit: TerminalScrollbackLimit(rawValue: value(Preference.terminalScrollbackLimit)) ?? TerminalSettings.defaultScrollbackLimit,
                confirmCloseRunningProcess: value(Preference.terminalConfirmCloseRunningProcess),
                pinPromptToBottom: value(Preference.terminalPinPromptToBottom)
            )
        }
        nonmutating set {
            store(newValue.themeOverride, for: Preference.terminalTheme)
            store(TerminalSettings.cleanFontFamily(newValue.fontFamilyOverride), for: Preference.terminalFontFamily)
            store(newValue.fontSizeOverride.map(TerminalSettings.clampFontSize), for: Preference.terminalFontSize)
            store(newValue.fontLigaturesOverride, for: Preference.terminalFontLigatures)
            store(newValue.fontThicken, for: Preference.terminalFontThicken)
            store(newValue.cursorStyle, for: Preference.terminalCursorStyle)
            store(newValue.cursorBlink, for: Preference.terminalCursorBlink)
            store(TerminalSettings.clampPadding(newValue.paddingX), for: Preference.terminalPaddingX)
            store(TerminalSettings.clampPadding(newValue.paddingY), for: Preference.terminalPaddingY)
            store(TerminalSettings.clampMinimumContrast(newValue.minimumContrast), for: Preference.terminalMinimumContrast)
            store(newValue.dimInactivePanes, for: Preference.terminalPanesDimInactive)
            store(newValue.focusFollowsMouse, for: Preference.terminalPanesFocusFollowsMouse)
            store(newValue.optionAsAlt, for: Preference.terminalInputOptionAsAlt)
            store(newValue.copyOnSelect, for: Preference.terminalInputCopyOnSelect)
            store(newValue.scrollbackLimit.rawValue, for: Preference.terminalScrollbackLimit)
            store(newValue.confirmCloseRunningProcess, for: Preference.terminalConfirmCloseRunningProcess)
            store(newValue.pinPromptToBottom, for: Preference.terminalPinPromptToBottom)
        }
    }

    /// Clears only embedded terminal settings back to defaults.
    public func resetTerminal() { reset(.terminal) }

    /// Takes the keys of one page out (the schema says which: `design/preferences.json`), so it reads as its defaults again; the other pages are not touched.
    public func reset(_ page: SettingsPage) { Preference.reset(page, in: defaults) }
}

/// The provider (a chat agent's name), model and reasoning a new session opens with, and what it may do (the options about access, by the
/// provider's own option id: Claude's permission mode, Codex's approvals and sandbox); an empty one is the provider's own.
public struct NewSessionStart: Equatable {
    public var agent: String
    public var model: String
    public var effort: String
    public var access: [String: String]

    public init(agent: String = "", model: String = "", effort: String = "", access: [String: String] = [:]) {
        self.agent = agent
        self.model = model
        self.effort = effort
        self.access = access
    }

    /// The access as it is kept in a preference: a JSON object of option and value. Anything else reads as none.
    public static func access(fromJSON text: String) -> [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(text.utf8))) ?? [:]
    }

    public static func json(fromAccess access: [String: String]) -> String {
        (try? JSONEncoder().encode(access)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

/// Where a new session opens when its folder offers a worktree; a draft's own choice stays above it.
public enum WorkIn: String, CaseIterable, Sendable {
    case baseFolder, newWorktree

    public var title: String { self == .baseFolder ? "The base folder" : "A new worktree" }
}

public enum ColorSchemeChoice: String, CaseIterable {
    case system, light, dark

    public var title: String { rawValue.capitalized }
}

/// How tight the app packs its rows: the vertical padding of a sidebar row and the space between the messages of a conversation.
public enum Density: String, CaseIterable {
    case compact, comfortable

    public var title: String { rawValue.capitalized }
    public var rowPadding: CGFloat { self == .compact ? 4 : 7 }
    /// A session's row in the sidebar has room around its lines: it can have three of them.
    public var sessionRowPadding: CGFloat { self == .compact ? 7 : 12 }
    public var sessionLineGap: CGFloat { self == .compact ? 3 : 5 }
}

/// The text of the messages: the chat's own size in points, which the text size of the app does not multiply.
public enum ChatText {
    public static let defaultSize: CGFloat = 13
    public static let sizeRange: ClosedRange<CGFloat> = 11...20

    /// `size` rounded to a whole point and kept inside `sizeRange`; the default for a number that is not one.
    public static func clamped(_ size: CGFloat) -> CGFloat {
        size.isNaN ? defaultSize : min(max(size.rounded(), sizeRange.lowerBound), sizeRange.upperBound)
    }
}

/// The room between the lines of a message, on top of the font's own.
public enum ChatLineSpacing: String, CaseIterable {
    case tight, normal, loose

    public var title: String { rawValue.capitalized }

    /// A share of the font's size: normal is the 4 points a 13-point message has always had.
    public func extra(forSize size: CGFloat) -> CGFloat {
        switch self {
        case .tight: size * 2 / 13
        case .normal: size * 4 / 13
        case .loose: size * 7 / 13
        }
    }

    /// What the person's bubble adds: it never had room between its lines, so Normal adds none and Loose only what it has over Normal.
    public func extraOverNormal(forSize size: CGFloat) -> CGFloat { max(0, extra(forSize: size) - Self.normal.extra(forSize: size)) }
}

/// The room between the messages of a conversation, in points.
public enum MessageSpacing: String, CaseIterable {
    case compact, comfortable, spacious

    public var title: String { rawValue.capitalized }
    public var gap: CGFloat {
        switch self {
        case .compact: 8
        case .comfortable: 12
        case .spacious: 20
        }
    }
}

/// How wide the column of a conversation is, in points: the most its messages take before they wrap.
public enum MessageWidth: String, CaseIterable {
    case narrow, medium, wide, ultraWide, widest

    public var title: String {
        switch self {
        case .ultraWide: "Ultra wide"
        default: rawValue.capitalized
        }
    }

    public var points: CGFloat {
        switch self {
        case .narrow: 640
        case .medium: 760
        case .wide: 880
        case .ultraWide: 1040
        case .widest: 1280
        }
    }
}

/// What the conversation's surfaces are made of: glass blurs what is under them, flat is a quiet solid fill with a fine edge.
public enum ChatSurface: String, CaseIterable {
    case glass, flat

    public var title: String { rawValue.capitalized }
}

/// When a message shows the time it was written.
public enum MessageTimes: String, CaseIterable {
    case never, hover, always

    public var title: String { rawValue == "hover" ? "On hover" : rawValue.capitalized }

    /// Whether the time shows, given whether the pointer is over the message.
    public func shows(hovering: Bool) -> Bool { self == .always || (self == .hover && hovering) }
}

/// The key that sends a message: Return, or ⌘Return. Shift+Return makes a new line whichever is chosen.
public enum SendKey: String, CaseIterable {
    case `return`, commandReturn

    /// Whether Return pressed with these modifiers sends; if not, it makes a new line.
    public func sends(command: Bool, shift: Bool) -> Bool {
        guard shift == false else { return false }
        return self == .commandReturn ? command : command == false
    }
}

/// What sending does while the agent answers: hold the message until the turn ends, or stop the turn and send it.
public enum WhileWorking: String, CaseIterable {
    case queue, interrupt
}

/// What the agent's tools show in a conversation: nothing, each run folded, or every call open.
public enum ToolOutputMode: String, CaseIterable {
    case hidden, collapsed, expanded

    public var title: String { rawValue.capitalized }

    /// Whether a run or a call opens by itself: every one when expanded, and the ones that failed while the person wants that; never hidden.
    public func opens(failed: Bool, opensFailed: Bool) -> Bool {
        switch self {
        case .hidden: false
        case .collapsed: failed && opensFailed
        case .expanded: true
        }
    }
}

/// How an edit's diff reads in a conversation.
public enum DiffStyle: String, CaseIterable {
    case unified, split

    public var title: String { rawValue.capitalized }
}

/// How many lines of an output show before Show more.
public enum OutputLength: Int, CaseIterable {
    case short = 20, medium = 50, long = 100

    public var title: String { "\(rawValue) lines" }

    /// The first lines of an output and how many are left out; all of it once expanded.
    public func visible(_ lines: [String], expanded: Bool) -> (lines: [String], hidden: Int) {
        guard expanded == false, lines.count > rawValue else { return (lines, 0) }
        return (Array(lines.prefix(rawValue)), lines.count - rawValue)
    }
}

/// Stop asks first only when it interrupts epics and the person did not switch the question off.
public func asksBeforeStopping(_ snapshot: PanelSnapshot, switchOn: Bool) -> Bool {
    switchOn && snapshot.stopNeedsConfirmation
}
