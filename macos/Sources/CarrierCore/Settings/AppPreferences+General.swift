import Foundation

extension AppPreferences {
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
}
