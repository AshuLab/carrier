import Foundation

/// The App group's preferences, kept in user defaults so they hold across a relaunch: each with its default, and a bad saved value
/// reads as the default. The keys are the ones that already existed, so nothing a person set is lost.
public struct AppPreferences {
    public static let styleKey = "menu.iconStyle"
    public static let animatesKey = "menu.animate"
    public static let confirmStopKey = "stop.confirm"
    public static let timeStyleKey = "display.timeStyle"
    public static let clockHoursKey = "display.clock"
    public static let colorSchemeKey = "appearance.colorScheme"
    public static let densityKey = "appearance.density"
    public static let themeKey = "appearance.theme"
    public static let accentKey = "appearance.accent"
    public static let tintKey = "appearance.tint"
    public static let translucentKey = "appearance.translucent"
    public static let monospaceFamilyKey = "appearance.mono.family"
    public static let monospaceSizeKey = "appearance.mono.size"
    public static let monospaceLineHeightKey = "appearance.mono.lineHeight"
    public static let monospaceLigaturesKey = "appearance.mono.ligatures"
    public static let monospaceWrapKey = "appearance.mono.wrap"
    public static let monospaceLineNumbersKey = "appearance.mono.lineNumbers"
    public static let statesByShapeKey = "appearance.statesByShape"
    public static let messageWidthKey = "appearance.messageWidth"
    public static let sendKeyKey = "chat.sendKey"
    public static let whileWorkingKey = "chat.whileWorking"
    public static let writingToolsKey = "chat.writingTools"
    public static let checksSpellingKey = "chat.checkSpelling"
    public static let correctsSpellingKey = "chat.correctSpelling"
    public static let followsOutputKey = "chat.followOutput"
    public static let messageTimesKey = "chat.messageTimes"
    public static let toolOutputKey = "chat.toolOutput"
    public static let opensFailedCallsKey = "chat.opensFailedCalls"
    public static let diffStyleKey = "chat.diffStyle"
    public static let outputLengthKey = "chat.outputLength"
    public static let confirmDeleteKey = "chat.confirmDelete"
    public static let showsReasoningKey = "chat.showReasoning"
    public static let newSessionAgentKey = "chat.newSession.agent"
    public static let newSessionModelKey = "chat.newSession.model"
    public static let newSessionEffortKey = "chat.newSession.effort"
    public static let newSessionAccessKey = "chat.newSession.access"
    public static let workInKey = "chat.newSession.workIn"
    public static let dictationEnabledKey = "dictation.enabled"
    public static let dictationModelKey = "dictation.model"
    public static let dictationLanguageKey = "dictation.language"
    public static let terminalThemeKey = "terminal.theme"
    public static let terminalFontFamilyKey = "terminal.font.family"
    public static let terminalFontSizeKey = "terminal.font.size"
    public static let terminalFontLigaturesKey = "terminal.font.ligatures"
    public static let terminalCursorStyleKey = "terminal.cursor.style"
    public static let terminalCursorBlinkKey = "terminal.cursor.blink"
    public static let terminalPaddingXKey = "terminal.padding.x"
    public static let terminalPaddingYKey = "terminal.padding.y"
    public static let terminalMinimumContrastKey = "terminal.minimumContrast"
    public static let terminalConfirmCloseKey = "terminal.confirmCloseRunningProcess"

    public static let defaultStyle = IconStyle.countAndBar
    public static let defaultAnimates = true
    public static let defaultShowsEpics = true
    public static let defaultConfirmStop = true
    public static let defaultColorScheme = ColorSchemeChoice.system
    public static let defaultDensity = Density.comfortable
    public static let defaultMessageWidth = MessageWidth.medium
    public static let defaultTheme = Theme.carrier
    public static let defaultTint = Tint.off
    public static let defaultSendKey = SendKey.return
    public static let defaultWhileWorking = WhileWorking.queue
    public static let defaultWritingTools = false
    public static let defaultChecksSpelling = true
    public static let defaultCorrectsSpelling = false
    public static let defaultFollowsOutput = true
    public static let defaultMessageTimes = MessageTimes.hover
    public static let defaultToolOutput = ToolOutputMode.collapsed
    public static let defaultOpensFailedCalls = true
    public static let defaultDiffStyle = DiffStyle.unified
    public static let defaultOutputLength = OutputLength.short
    public static let defaultConfirmDelete = true
    public static let defaultWorkIn = WorkIn.baseFolder
    public static let defaultShowsReasoning = true
    public static let defaultDictationEnabled = true

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// What a new session opens with: the provider, its model and its reasoning. Each is empty when the person chose none, and the session
    /// then takes the first provider that can work and that provider's own model and level.
    public var newSessionStart: NewSessionStart {
        NewSessionStart(
            agent: defaults.string(forKey: Self.newSessionAgentKey) ?? "",
            model: defaults.string(forKey: Self.newSessionModelKey) ?? "",
            effort: defaults.string(forKey: Self.newSessionEffortKey) ?? "",
            access: NewSessionStart.access(fromJSON: defaults.string(forKey: Self.newSessionAccessKey) ?? "")
        )
    }

    public var style: IconStyle {
        get { defaults.string(forKey: Self.styleKey).flatMap(IconStyle.init(rawValue:)) ?? Self.defaultStyle }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.styleKey) }
    }

    public var animates: Bool {
        get { defaults.object(forKey: Self.animatesKey) as? Bool ?? Self.defaultAnimates }
        nonmutating set { defaults.set(newValue, forKey: Self.animatesKey) }
    }

    public var showsEpics: Bool {
        get { defaults.object(forKey: showEpicsKey) as? Bool ?? Self.defaultShowsEpics }
        nonmutating set { defaults.set(newValue, forKey: showEpicsKey) }
    }

    /// Whether stopping Carrier asks first when it would interrupt epics.
    public var confirmStop: Bool {
        get { defaults.object(forKey: Self.confirmStopKey) as? Bool ?? Self.defaultConfirmStop }
        nonmutating set { defaults.set(newValue, forKey: Self.confirmStopKey) }
    }

    /// How ages and times read everywhere in the app: relative or as a clock time.
    public var timeStyle: TimeStyle {
        get { defaults.string(forKey: Self.timeStyleKey).flatMap(TimeStyle.init(rawValue:)) ?? .relative }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.timeStyleKey) }
    }

    /// The clock of clock times: the Mac's, 12 or 24 hours.
    public var clockHours: ClockHours {
        get { defaults.string(forKey: Self.clockHoursKey).flatMap(ClockHours.init(rawValue:)) ?? .system }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.clockHoursKey) }
    }

    /// The appearance of every window of the app: the Mac's, or light or dark whatever the Mac is.
    public var colorScheme: ColorSchemeChoice {
        get { defaults.string(forKey: Self.colorSchemeKey).flatMap(ColorSchemeChoice.init(rawValue:)) ?? Self.defaultColorScheme }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.colorSchemeKey) }
    }

    /// The text size of the whole interface in percent, the one the type scale reads.
    public var textSize: Int {
        get { TypeScale.stored(in: defaults).percent }
        nonmutating set { defaults.set(TypeScale(percent: newValue).percent, forKey: TypeScale.percentKey) }
    }

    public var density: Density {
        get { defaults.string(forKey: Self.densityKey).flatMap(Density.init(rawValue:)) ?? Self.defaultDensity }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.densityKey) }
    }

    public var theme: Theme {
        get { defaults.string(forKey: Self.themeKey).flatMap(Theme.init(rawValue:)) ?? Self.defaultTheme }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.themeKey) }
    }

    /// The accent the person picked; nil is the theme's own.
    public var accent: AccentColor? {
        get { defaults.string(forKey: Self.accentKey).flatMap(AccentColor.init(rawValue:)) }
        nonmutating set { defaults.set(newValue?.rawValue, forKey: Self.accentKey) }
    }

    public var tint: Tint {
        get { defaults.string(forKey: Self.tintKey).flatMap(Tint.init(rawValue:)) ?? Self.defaultTint }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.tintKey) }
    }

    /// Whether windows are translucent: what the person chose, and while they did not, the opposite of the system's Reduce transparency.
    public func translucent(systemReducesTransparency: Bool) -> Bool {
        defaults.object(forKey: Self.translucentKey) as? Bool ?? (systemReducesTransparency == false)
    }

    public func setTranslucent(_ value: Bool) { defaults.set(value, forKey: Self.translucentKey) }

    /// The font, size, line height, ligatures, wrapping and line numbers of code and output; a bad saved value reads as its default.
    public var monospace: MonospaceSettings {
        get {
            let standard = MonospaceSettings()
            let size = defaults.object(forKey: Self.monospaceSizeKey) as? Double
            return MonospaceSettings(
                family: defaults.string(forKey: Self.monospaceFamilyKey) ?? standard.family,
                size: size.map { min(max(CGFloat($0), MonospaceSettings.sizeRange.lowerBound), MonospaceSettings.sizeRange.upperBound) } ?? standard.size,
                lineHeight: defaults.string(forKey: Self.monospaceLineHeightKey).flatMap(LineHeight.init(rawValue:)) ?? standard.lineHeight,
                ligatures: defaults.object(forKey: Self.monospaceLigaturesKey) as? Bool ?? standard.ligatures,
                wrapLongLines: defaults.object(forKey: Self.monospaceWrapKey) as? Bool ?? standard.wrapLongLines,
                lineNumbers: defaults.object(forKey: Self.monospaceLineNumbersKey) as? Bool ?? standard.lineNumbers
            )
        }
        nonmutating set {
            defaults.set(newValue.family, forKey: Self.monospaceFamilyKey)
            defaults.set(Double(newValue.size), forKey: Self.monospaceSizeKey)
            defaults.set(newValue.lineHeight.rawValue, forKey: Self.monospaceLineHeightKey)
            defaults.set(newValue.ligatures, forKey: Self.monospaceLigaturesKey)
            defaults.set(newValue.wrapLongLines, forKey: Self.monospaceWrapKey)
            defaults.set(newValue.lineNumbers, forKey: Self.monospaceLineNumbersKey)
        }
    }

    /// Whether each state wears a symbol beside its color, so that color is not the only clue.
    public var statesByShape: Bool {
        get { defaults.object(forKey: Self.statesByShapeKey) as? Bool ?? false }
        nonmutating set { defaults.set(newValue, forKey: Self.statesByShapeKey) }
    }

    /// How wide a conversation gets before its messages wrap.
    public var messageWidth: MessageWidth {
        get { defaults.string(forKey: Self.messageWidthKey).flatMap(MessageWidth.init(rawValue:)) ?? Self.defaultMessageWidth }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.messageWidthKey) }
    }

    /// The key that sends in the message box; the other one makes a new line.
    public var sendKey: SendKey {
        get { defaults.string(forKey: Self.sendKeyKey).flatMap(SendKey.init(rawValue:)) ?? Self.defaultSendKey }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.sendKeyKey) }
    }

    /// What sending does while the agent answers.
    public var whileWorking: WhileWorking {
        get { defaults.string(forKey: Self.whileWorkingKey).flatMap(WhileWorking.init(rawValue:)) ?? Self.defaultWhileWorking }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.whileWorkingKey) }
    }

    /// Whether the system's Writing Tools offer to rewrite the text of the message box.
    public var writingTools: Bool {
        get { defaults.object(forKey: Self.writingToolsKey) as? Bool ?? Self.defaultWritingTools }
        nonmutating set { defaults.set(newValue, forKey: Self.writingToolsKey) }
    }

    public var checksSpelling: Bool {
        get { defaults.object(forKey: Self.checksSpellingKey) as? Bool ?? Self.defaultChecksSpelling }
        nonmutating set { defaults.set(newValue, forKey: Self.checksSpellingKey) }
    }

    public var correctsSpelling: Bool {
        get { defaults.object(forKey: Self.correctsSpellingKey) as? Bool ?? Self.defaultCorrectsSpelling }
        nonmutating set { defaults.set(newValue, forKey: Self.correctsSpellingKey) }
    }

    /// Whether a conversation scrolls to new output while the person is at its end.
    public var followsOutput: Bool {
        get { defaults.object(forKey: Self.followsOutputKey) as? Bool ?? Self.defaultFollowsOutput }
        nonmutating set { defaults.set(newValue, forKey: Self.followsOutputKey) }
    }

    /// Whether messages show the time they were written, written in the General format.
    public var messageTimes: MessageTimes {
        get { defaults.string(forKey: Self.messageTimesKey).flatMap(MessageTimes.init(rawValue:)) ?? Self.defaultMessageTimes }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.messageTimesKey) }
    }

    /// What the agent's tools show in a conversation.
    public var toolOutput: ToolOutputMode {
        get { defaults.string(forKey: Self.toolOutputKey).flatMap(ToolOutputMode.init(rawValue:)) ?? Self.defaultToolOutput }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.toolOutputKey) }
    }

    /// Whether a call that failed opens by itself, whatever the mode but hidden.
    public var opensFailedCalls: Bool {
        get { defaults.object(forKey: Self.opensFailedCallsKey) as? Bool ?? Self.defaultOpensFailedCalls }
        nonmutating set { defaults.set(newValue, forKey: Self.opensFailedCallsKey) }
    }

    /// How an edit's diff reads: its lines one under the other, or removed and added side by side.
    public var diffStyle: DiffStyle {
        get { defaults.string(forKey: Self.diffStyleKey).flatMap(DiffStyle.init(rawValue:)) ?? Self.defaultDiffStyle }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.diffStyleKey) }
    }

    /// How many lines of an output show before Show more.
    public var outputLength: OutputLength {
        get { OutputLength(rawValue: defaults.integer(forKey: Self.outputLengthKey)) ?? Self.defaultOutputLength }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.outputLengthKey) }
    }

    /// Whether the agent's reasoning shows folded under its message, when the host sends it.
    public var showsReasoning: Bool {
        get { defaults.object(forKey: Self.showsReasoningKey) as? Bool ?? Self.defaultShowsReasoning }
        nonmutating set { defaults.set(newValue, forKey: Self.showsReasoningKey) }
    }

    /// Whether deleting a session asks first.
    public var confirmDelete: Bool {
        get { defaults.object(forKey: Self.confirmDeleteKey) as? Bool ?? Self.defaultConfirmDelete }
        nonmutating set { defaults.set(newValue, forKey: Self.confirmDeleteKey) }
    }

    /// Where a new session opens: the base folder, or a new worktree when its folder offers one.
    public var workIn: WorkIn {
        get { defaults.string(forKey: Self.workInKey).flatMap(WorkIn.init(rawValue:)) ?? Self.defaultWorkIn }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.workInKey) }
    }

    /// Whether the message box has a microphone: Dictation is on until the person turns it off.
    public var dictationEnabled: Bool {
        get { defaults.object(forKey: Self.dictationEnabledKey) as? Bool ?? Self.defaultDictationEnabled }
        nonmutating set { defaults.set(newValue, forKey: Self.dictationEnabledKey) }
    }

    /// The id of the speech model the person chose; nil while they did not.
    public var dictationModelID: String? {
        get { defaults.string(forKey: Self.dictationModelKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.dictationModelKey) }
    }

    /// The chosen speech model among those on offer: Apple's when none was chosen or the saved one is not on offer any more.
    public func dictationModel(among models: [SpeechModel]) -> SpeechModel? {
        models.first { $0.id == dictationModelID } ?? models.first { $0.recognizer == .apple }
    }

    /// The language the person chose, `automaticLanguage` or a base code; nil while they did not (`languageChoices` says what that is).
    public var dictationLanguage: String? {
        get { defaults.string(forKey: Self.dictationLanguageKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.dictationLanguageKey) }
    }

    /// Settings for the embedded terminal (theme override, font overrides, cursor, padding, contrast, close confirmation).
    public var terminal: TerminalSettings {
        get {
            TerminalSettings(
                themeOverride: defaults.string(forKey: Self.terminalThemeKey).flatMap(Theme.init(rawValue:)),
                fontFamilyOverride: defaults.string(forKey: Self.terminalFontFamilyKey),
                fontSizeOverride: defaults.object(forKey: Self.terminalFontSizeKey) as? Double,
                fontLigaturesOverride: defaults.object(forKey: Self.terminalFontLigaturesKey) as? Bool,
                cursorStyle: defaults.string(forKey: Self.terminalCursorStyleKey).flatMap(TerminalCursorStyleChoice.init(rawValue:)) ?? TerminalSettings.defaultCursorStyle,
                cursorBlink: defaults.object(forKey: Self.terminalCursorBlinkKey) as? Bool ?? TerminalSettings.defaultCursorBlink,
                paddingX: defaults.object(forKey: Self.terminalPaddingXKey) as? Double ?? TerminalSettings.defaultPaddingX,
                paddingY: defaults.object(forKey: Self.terminalPaddingYKey) as? Double ?? TerminalSettings.defaultPaddingY,
                minimumContrast: defaults.object(forKey: Self.terminalMinimumContrastKey) as? Double ?? TerminalSettings.defaultMinimumContrast,
                confirmCloseRunningProcess: defaults.object(forKey: Self.terminalConfirmCloseKey) as? Bool ?? TerminalSettings.defaultConfirmCloseRunningProcess
            )
        }
        nonmutating set {
            if let theme = newValue.themeOverride {
                defaults.set(theme.rawValue, forKey: Self.terminalThemeKey)
            } else {
                defaults.removeObject(forKey: Self.terminalThemeKey)
            }
            if let family = TerminalSettings.cleanFontFamily(newValue.fontFamilyOverride) {
                defaults.set(family, forKey: Self.terminalFontFamilyKey)
            } else {
                defaults.removeObject(forKey: Self.terminalFontFamilyKey)
            }
            if let size = newValue.fontSizeOverride {
                defaults.set(TerminalSettings.clampFontSize(size), forKey: Self.terminalFontSizeKey)
            } else {
                defaults.removeObject(forKey: Self.terminalFontSizeKey)
            }
            if let ligatures = newValue.fontLigaturesOverride {
                defaults.set(ligatures, forKey: Self.terminalFontLigaturesKey)
            } else {
                defaults.removeObject(forKey: Self.terminalFontLigaturesKey)
            }
            defaults.set(newValue.cursorStyle.rawValue, forKey: Self.terminalCursorStyleKey)
            defaults.set(newValue.cursorBlink, forKey: Self.terminalCursorBlinkKey)
            defaults.set(TerminalSettings.clampPadding(newValue.paddingX), forKey: Self.terminalPaddingXKey)
            defaults.set(TerminalSettings.clampPadding(newValue.paddingY), forKey: Self.terminalPaddingYKey)
            defaults.set(TerminalSettings.clampMinimumContrast(newValue.minimumContrast), forKey: Self.terminalMinimumContrastKey)
            defaults.set(newValue.confirmCloseRunningProcess, forKey: Self.terminalConfirmCloseKey)
        }
    }

    public static let terminalKeys: [String] = [
        terminalThemeKey, terminalFontFamilyKey, terminalFontSizeKey, terminalFontLigaturesKey,
        terminalCursorStyleKey, terminalCursorBlinkKey, terminalPaddingXKey, terminalPaddingYKey,
        terminalMinimumContrastKey, terminalConfirmCloseKey,
    ]

    /// Clears only embedded terminal settings back to defaults.
    public func resetTerminal() {
        for key in Self.terminalKeys { defaults.removeObject(forKey: key) }
    }

    /// Takes the keys of one page out, so it reads as its defaults again; the other pages are not touched.
    public func reset(_ page: SettingsPage) {
        for key in Self.keys(of: page) { defaults.removeObject(forKey: key) }
    }

    // the pages that gain preferences add their keys here
    private static func keys(of page: SettingsPage) -> [String] {
        switch page {
        case .general: [styleKey, animatesKey, showEpicsKey, timeStyleKey, clockHoursKey]
        case .sidebar:
            [
                SidebarStore.groupByKey, SidebarStore.sessionSortKey, SidebarStore.archiveSortKey, SidebarStore.archiveListSortKey, SidebarStore.showsIconKey,
                SidebarStore.showsBranchKey, SidebarStore.showsProvidersKey, SidebarStore.showsAgeKey,
            ]
        case .appearance:
            [
                colorSchemeKey, TypeScale.percentKey, densityKey, themeKey, accentKey, tintKey, translucentKey, statesByShapeKey, messageWidthKey,
                monospaceFamilyKey, monospaceSizeKey, monospaceLineHeightKey, monospaceLigaturesKey, monospaceWrapKey, monospaceLineNumbersKey,
            ]
        case .chat:
            [
                sendKeyKey, whileWorkingKey, writingToolsKey, checksSpellingKey, correctsSpellingKey, followsOutputKey, messageTimesKey,
                toolOutputKey, opensFailedCallsKey, diffStyleKey, outputLengthKey, showsReasoningKey,
            ]
        // the ages of the session clock live in chat.json: the page's own Reset writes them back
        case .sessions: [confirmDeleteKey, newSessionAgentKey, newSessionModelKey, newSessionEffortKey, newSessionAccessKey, workInKey]
        case .notifications:
            [
                notifyNeedsYouKey, notifyReadyForTestKey, notifyProblemKey, notifyChatNeedsAttentionKey, notifyChatDoneKey, notifyOnlyWhenAwayKey,
                notifyDockBadgeKey, notifySoundKey, notifyReminderKey, notifyQuietKey, notifyQuietStartKey, notifyQuietEndKey,
            ]
        case .dictation: [dictationEnabledKey, dictationModelKey, dictationLanguageKey]
        case .keybindings: [ShortcutTable.key]
        // the Providers page only reads, the Updates page writes Sparkle's own preferences, the Carrier pages write config.json or (Engine) a few switches that have no Reset, and the Legacy page keeps its own settings
        case .providers, .updates, .engine, .behavior, .repos, .agents, .health: []
        }
    }
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
public enum WorkIn: String, CaseIterable {
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
    public var messageGap: CGFloat { self == .compact ? 8 : 12 }
}

/// How wide the column of a conversation is, in points: the most its messages take before they wrap.
public enum MessageWidth: String, CaseIterable {
    case narrow, medium, wide, ultraWide

    public var title: String { self == .ultraWide ? "Ultra wide" : rawValue.capitalized }

    public var points: CGFloat {
        switch self {
        case .narrow: 640
        case .medium: 760
        case .wide: 880
        case .ultraWide: 1040
        }
    }
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
