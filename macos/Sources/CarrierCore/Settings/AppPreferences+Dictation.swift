import Foundation

extension AppPreferences {
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
}
