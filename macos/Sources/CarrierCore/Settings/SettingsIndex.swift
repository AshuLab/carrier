import Foundation

// What Settings can be searched for: every page, and the groups and rows of each, with the words the person sees. The window's search reads
// this (`settingsResults`) and the page scrolls to the row that was chosen, found again by `settingsAnchor`.
// A place is known by identifiers (the page's, the group's, the row's), never by its title, so a title can change or be translated and nothing
// that finds it breaks. A row or a group that is not here cannot be found, so a new one is added here in the same change:
// `SettingsIndexDriftTests` fails when a row the views draw has an identifier that is not in this list, and when one in this list is no longer drawn.
// The words are copy keys of design/copy/ (the same a page reads for the row, so the search finds a row by what the page calls it, in either
// language); an entry says which keys it was made from (`copyKeys`) so a test can check each one is in both languages.

/// The place a row has in Settings: its page, the group of rows it is in ("" for the page itself) and its title, each group and row with the
/// identifier its view carries (`SettingsTabRow(id:)`).
public struct SettingsEntry: Equatable, Sendable, Identifiable {
    public let page: SettingsPage
    public let groupID: String
    public let group: String
    public let rowID: String
    public let title: String
    public let detail: String
    /// Words a person may type for the row that no other of its words has; searched like the detail, never shown.
    public let keywords: String
    /// The page itself, found by its name: choosing it goes to the page, not to a row.
    public let isPage: Bool
    /// The screen inside the page this opens, for what only this Mac knows (a provider, an account); empty for a row of the page.
    public let path: [String]
    /// The copy keys the entry's own words were read from; empty for an entry whose words a model of the page gives or that is made of a value.
    public let copyKeys: [String]

    public init(
        page: SettingsPage, groupID: String = "", group: String = "", rowID: String = "", title: String, detail: String = "", keywords: String = "", isPage: Bool = false, path: [String] = [],
        copyKeys: [String] = []
    ) {
        self.page = page
        self.groupID = groupID
        self.group = group
        self.rowID = rowID
        self.title = title
        self.detail = detail
        self.keywords = keywords
        self.isPage = isPage
        self.path = path
        self.copyKeys = copyKeys
    }

    /// What the page scrolls to once the place is open: the row's own anchor (`settingsAnchor`), the page's identifier for a page.
    public var anchor: String { isPage ? settingsAnchor(page, group: "", row: "") : settingsAnchor(page, group: groupID, row: rowID) }

    /// What a row of a list is known by: the anchor, and with its path for a screen (two accounts of one provider may share a name).
    public var id: String { path.isEmpty ? anchor : ([anchor] + path).joined(separator: "/") }
}

/// The id a row carries in its page, so the page can scroll to it: the identifiers of its page, its group and its row. A group is its own
/// identifier with no row (`row` empty or the same as the group's), and a page is its identifier alone.
public func settingsAnchor(_ page: SettingsPage, group: String, row: String) -> String {
    [page.rawValue, group, row == group ? "" : row].filter { $0.isEmpty == false }.joined(separator: ".")
}

/// Every searchable place in the language of `bundle` and `locale`, in the order of the sidebar and of each page, so a search lists its results as
/// the pages are listed. The identifiers, the anchors and the order are the same in every language.
public func buildSettingsIndex(bundle: Bundle? = nil, locale: Locale = .current) -> [SettingsEntry] {
    let index = IndexBuilder(bundle: bundle, locale: locale)
    return SettingsPage.allCases.flatMap { settingsPage in
        [SettingsEntry(page: settingsPage, title: settingsPage.title(bundle: bundle, locale: locale), detail: settingsPage.detail(bundle: bundle, locale: locale), isPage: true)] + index.rows(of: settingsPage)
    }
}

/// Every searchable place in the app's language.
public let settingsIndex: [SettingsEntry] = buildSettingsIndex()

/// What reads the words of an entry: a row says its group, title and detail by copy key, and a row whose words a model of the page gives (a
/// shortcut, a behavior row, a role, a dictation screen) says them as they are.
private struct IndexBuilder {
    let bundle: Bundle?
    let locale: Locale

    private func words(_ key: String) -> String { Copy.word(key, bundle: bundle) ?? key }

    /// The rows of a group, each with the keys of its title and detail; `keywords` names, by row identifier, the key of a row's keywords.
    func page(_ settingsPage: SettingsPage, _ groupID: String, _ groupKey: String, _ rows: [(id: String, title: String, detail: String)], keywords: [String: String] = [:], path: [String] = []) -> [SettingsEntry] {
        rows.map { row in
            let keywordKey = keywords[row.id]
            let keys: [String] = ([groupKey, row.title, row.detail] + (keywordKey.map { [$0] } ?? [])).filter { $0.isEmpty == false }
            return SettingsEntry(
                page: settingsPage, groupID: groupID, group: groupKey.isEmpty ? "" : words(groupKey), rowID: row.id, title: words(row.title), detail: words(row.detail),
                keywords: keywordKey.map(words) ?? "", path: path, copyKeys: keys)
        }
    }

    /// The same for the screen of the Dictation page that draws the rows.
    func screen(_ screen: DictationScreen, _ groupID: String, _ groupKey: String, _ rows: [(id: String, title: String, detail: String)]) -> [SettingsEntry] {
        page(.dictation, groupID, groupKey, rows, path: [screen.rawValue])
    }

    /// Rows whose words are already in the language of the index, from the model that draws them.
    func given(_ settingsPage: SettingsPage, _ groupID: String, _ group: String, _ rows: [(id: String, title: String, detail: String)], path: [String] = []) -> [SettingsEntry] {
        rows.map { SettingsEntry(page: settingsPage, groupID: groupID, group: group, rowID: $0.id, title: $0.title, detail: $0.detail, path: path) }
    }

    func rows(of settingsPage: SettingsPage) -> [SettingsEntry] {
        switch settingsPage {
        case .general:
            return page(.general, "menu-bar", "generalMenuBar", [
                ("icon-style", "generalIconStyle", "generalIconStyleDetail"), ("animate-the-icon", "generalAnimate", "settingsIndexGeneralAnimateTheIconDetail"),
                ("list-epics-in-the-menu", "generalListEpics", "generalListEpicsDetail"),
            ]) + page(.general, "display", "generalDisplay", [
                ("time-format", "generalTimeFormat", "generalTimeFormatDetail"), ("clock", "generalClock", "generalClockDetail"),
            ])
        case .providers:
            return page(.providers, "accounts-that-need-attention", "providersGroupAttention", [("accounts-that-need-attention", "providersGroupAttention", "settingsIndexProvidersAccountsThatNeedAttentionDetail")])
                + page(.providers, "ai-providers", "providersGroupAI", [("ai-providers", "providersGroupAI", "settingsIndexProvidersAiProvidersDetail")])
                + page(.providers, "local-servers", "providersGroupServers", [("local-servers", "providersGroupServers", "settingsIndexProvidersLocalServersDetail")])
                + page(.providers, "text-generators", "providersGroupGenerators", [
                    ("text-generators", "providersGroupGenerators", "settingsIndexProvidersTextGeneratorsDetail"),
                    ("titles-of-earlier-sessions", "providersTitlesTitle", "providersTitlesDetail"),
                ])
        case .appearance:
            return page(.appearance, "theme", "appearanceTheme", [("theme", "appearanceTheme", "settingsIndexAppearanceThemeDetail")])
                + page(.appearance, "look", "appearanceLook", [
                    ("color-scheme", "appearanceColorScheme", "appearanceColorSchemeDetail"), ("text-size", "appearanceTextSize", "settingsIndexAppearanceTextSizeDetail"), ("icon-set", "appearanceIconSet", "settingsIndexAppearanceIconSetDetail"), ("icon-weight", "appearanceIconWeight", "settingsIndexAppearanceIconWeightDetail"),
                    ("density", "appearanceDensity", "appearanceDensityDetail"), ("tell-states-apart-by-shape", "appearanceByShape", "appearanceByShapeDetail"),
                ]) + page(.appearance, "color", "appearanceColor", [
                    ("accent-color", "appearanceAccent", "appearanceAccentDetail"), ("tint-the-windows", "appearanceTint", "appearanceTintDetail"),
                    ("translucent-windows", "appearanceTranslucent", "appearanceTranslucentDetail"),
                ]) + page(.appearance, "code-and-output", "appearanceCode", [
                    ("font", "appearanceFont", "appearanceFontDetail"), ("size", "appearanceSize", "appearanceSizeDetail"),
                    ("line-height", "appearanceLineHeight", "appearanceLineHeightDetail"), ("ligatures", "appearanceLigatures", "appearanceLigaturesDetail"),
                    ("wrap-long-lines", "appearanceWrap", "appearanceWrapDetail"), ("line-numbers", "appearanceLineNumbers", "appearanceLineNumbersDetail"),
                ])
        case .notifications:
            return page(.notifications, "carrier", "notificationsGroupCarrier", [
                ("needs-attention", "notificationsNeedsAttention", "notificationsNeedsAttentionDetail"), ("ready-for-test", "notificationsReady", "notificationsReadyDetail"),
                ("a-problem", "notificationsProblem", "notificationsProblemDetail"),
            ]) + page(.notifications, "chat", "notificationsGroupChat", [("needs-attention", "notificationsNeedsAttention", "notificationsChatNeedsAttentionDetail"), ("done", "notificationsChatDone", "notificationsChatDoneDetail")])
                + page(.notifications, "delivery", "notificationsGroupDelivery", [
                    ("only-when-carrier-is-not-in-front", "notificationsOnlyAway", "notificationsOnlyAwayDetail"),
                    ("dock-badge", "notificationsDock", "settingsIndexNotificationsDockBadgeDetail"), ("play-a-sound", "notificationsSound", "notificationsSoundDetail"),
                    ("remind-me-again", "notificationsRemind", "settingsIndexNotificationsRemindMeAgainDetail"), ("quiet-hours", "notificationsQuiet", "settingsIndexNotificationsQuietHoursDetail"),
                    ("from", "notificationsFrom", "notificationsFromDetail"), ("until", "notificationsUntil", "settingsIndexNotificationsUntilDetail"),
                ]) + page(.notifications, "permission", "notificationsGroupPermission", [("system-permission", "notificationsPermission", "settingsIndexNotificationsSystemPermissionDetail")])
        case .keybindings:
            // the titles of the shortcuts and of their groups are keys the enums read; the line under each is a key
            return ShortcutGroup.allCases.flatMap { group in
                ShortcutCommand.allCases.filter { $0.group == group }.map { command in
                    let combo = command.defaultCombo?.text
                    let detail = combo.map { Copy.settingsIndexShortcutDefault(combo: $0, bundle: bundle, locale: locale) } ?? Copy.settingsIndexShortcutNone(bundle: bundle, locale: locale)
                    return SettingsEntry(
                        page: .keybindings, groupID: group.rawValue, group: group.title(bundle: bundle, locale: locale), rowID: command.rawValue, title: command.title(bundle: bundle, locale: locale), detail: detail,
                        copyKeys: [combo == nil ? "settingsIndexShortcutNone" : "settingsIndexShortcutDefault"])
                }
            }
        case .dictation:
            // the rows of the first screen that open a screen are the way to it from a search
            let opens = DictationScreen.allCases.map { screen in
                let yours = screen == .history || screen == .statistics
                let groupKey = yours ? "dictationGroupYours" : "dictationGroupSetUp"
                return SettingsEntry(
                    page: .dictation, groupID: yours ? "your-dictations" : "set-up", group: words(groupKey), rowID: screen.rawValue, title: screen.title(bundle: bundle, locale: locale),
                    detail: screen.detail(bundle: bundle, locale: locale), path: [screen.rawValue], copyKeys: [groupKey])
            }
            return opens + page(.dictation, "dictation", "dictationSwitch", [("microphone", "dictationItemMicrophone", "settingsIndexDictationMicrophoneDetail")])
                + screen(.recognition, "speech-models", "dictationGroupModels", [("speech-models", "dictationGroupModels", "settingsIndexDictationSpeechModelsDetail")])
                + screen(.recognition, "", "", [("language", "dictationLanguage", "settingsIndexDictationLanguageDetail")])
                + screen(.recognition, "memory", "dictationGroupMemory", [
                    ("keep-the-speech-model-ready", "dictationKeepReady", "settingsIndexDictationKeepTheSpeechModelReadyDetail"),
                    ("release-the-model-after", "dictationReleaseTitle", "settingsIndexDictationReleaseTheModelAfterDetail"),
                ])
                + screen(.recognition, "storage", "dictationGroupStorage", [("downloaded-models", "dictationDownloadedModels", "settingsIndexDictationDownloadedModelsDetail")])
                + screen(.global, "global-dictation", "dictationGroupGlobal", [
                    ("dictate-in-any-app", "dictationAnyApp", "settingsIndexDictationDictateInAnyAppDetail"), ("accessibility", "dictationItemAccessibility", "settingsIndexDictationAccessibilityDetail"),
                    ("shortcut", "dictationShortcutTitle", "settingsIndexDictationShortcutDetail"), ("activation", "dictationActivationTitle", "settingsIndexDictationActivationDetail"),
                ])
                + screen(.global, "widget", "dictationGroupWidget", [
            ("widget-style", "dictationWidgetStyle", "settingsIndexDictationWidgetStyleDetail"), ("widget-theme", "dictationWidgetTheme", "settingsIndexDictationWidgetThemeDetail"),
            ("live-text", "dictationLiveText", "settingsIndexDictationLiveTextDetail"),
            ("position", "dictationPosition", "settingsIndexDictationPositionDetail"),
        ])
                + screen(.cleanup, "cleanup", "cleanupGroupTitle", [
                    ("clean-the-text-with-a-model", "cleanupGroupToggle", "cleanupGroupServerDetail"), ("server", "cleanupGroupServer", "settingsIndexDictationServerDetail"),
                    ("model", "cleanupGroupModel", "settingsIndexDictationModelDetail"), ("prompt", "cleanupGroupPrompt", "settingsIndexDictationPromptDetail"), ("try-it", "cleanupGroupTry", "settingsIndexDictationTryItDetail"),
                ])
                + screen(.sounds, "sounds", "dictationGroupSounds", [("start-sound", "dictationStartSound", "dictationStartSoundDetail"), ("end-sound", "dictationEndSound", "settingsIndexDictationEndSoundDetail"), ("volume", "dictationVolume", "settingsIndexDictationVolumeDetail")])
                + screen(.history, "history", "dictationGroupHistory", [
                    ("keep-the-text-of-my-dictations", "dictationKeepText", "settingsIndexDictationKeepTheTextOfMyDictationsDetail"), ("keep-the-audio", "dictationKeepAudio", "settingsIndexDictationKeepTheAudioDetail"),
                    ("delete-audio-older-than", "dictationDeleteAudio", "dictationTranscriptsStay"), ("audio-on-disk", "dictationAudioOnDiskTitle", "settingsIndexDictationAudioOnDiskDetail"),
                ])
                + screen(.statistics, "overview", "dictationGroupOverview", [("overview", "dictationGroupOverview", "settingsIndexDictationOverviewDetail")])
                + screen(.statistics, "by-hour-of-the-day", "dictationGroupHours", [("by-hour-of-the-day", "dictationGroupHours", "settingsIndexDictationByHourOfTheDayDetail")])
                + screen(.statistics, "this-week", "dictationGroupWeek", [("this-week", "dictationGroupWeek", "settingsIndexDictationThisWeekDetail")])
                + screen(.statistics, "records", "dictationGroupRecords", [("records", "dictationGroupRecords", "settingsIndexDictationRecordsDetail")])
                + screen(.statistics, "statistics-settings", "dictationGroupStatsSettings", [("typing-speed", "dictationTypingSpeed", "settingsIndexDictationTypingSpeedDetail"), ("reset-statistics", "dictationResetStats", "settingsIndexDictationResetStatisticsDetail")])
        case .keepAwake:
            return page(.keepAwake, "now", "awakeGroupNow", [("now", "awakeGroupNow", "settingsIndexKeepAwakeNowDetail")])
                + page(.keepAwake, "by-hand", "awakeGroupByHand", [
                    ("length", "awakeRowLength", "awakeRowLengthDetail"), ("keep-the-screen-on", "awakeRowScreen", "settingsIndexKeepAwakeKeepTheScreenOnDetail"),
                    ("shortcut", "awakeRowShortcut", "settingsIndexKeepAwakeShortcutDetail"),
                ])
                + page(.keepAwake, "with-agents", "awakeGroupAgents", [
                    ("keep-awake-while-agents-work", "awakeRowAgents", "settingsIndexKeepAwakeKeepAwakeWhileAgentsWorkDetail"), ("stay-awake-after-they-finish", "awakeRowGrace", "awakeRowGraceDetail"),
                ])
                + page(.keepAwake, "battery-and-notices", "awakeGroupBattery", [
                    ("on-battery", "awakeRowBattery", "settingsIndexKeepAwakeOnBatteryDetail"), ("tell-me-when-it-stops-by-itself", "awakeRowNotify", "settingsIndexKeepAwakeTellMeWhenItStopsByItselfDetail"),
                ])
        case .chat:
            return page(.chat, "message-box", "chatSettingsMessageBox", [
                ("send-with", "chatSettingsSendWith", "chatSettingsSendWithDetail"), ("while-the-agent-works", "chatSettingsWhileWorking", "chatSettingsWhileWorkingDetail"),
                ("writing-tools", "chatSettingsWritingTools", "chatSettingsWritingToolsDetail"), ("check-spelling", "chatSettingsCheckSpelling", "chatSettingsCheckSpellingDetail"),
                ("correct-spelling-automatically", "chatSettingsCorrectSpelling", "chatSettingsCorrectSpellingDetail"),
                ("context-and-limits", "chatSettingsContextAndLimits", "chatSettingsContextAndLimitsDetail"),
            ]) + page(.chat, "conversation", "chatSettingsConversation", [
                ("follow-new-output", "chatSettingsFollowOutput", "chatSettingsFollowOutputDetail"), ("message-times", "chatSettingsMessageTimes", "settingsIndexChatMessageTimesDetail"),
                ("tool-output", "chatSettingsToolOutput", "chatSettingsToolOutputDetail"), ("open-the-calls-that-failed", "chatSettingsOpenFailed", "settingsIndexChatOpenTheCallsThatFailedDetail"),
                ("diff-style", "chatSettingsDiffStyle", "chatSettingsDiffStyleDetail"), ("output-length", "chatSettingsOutputLength", "chatSettingsOutputLengthDetail"),
                ("show-reasoning", "chatSettingsShowReasoning", "settingsIndexChatShowReasoningDetail"), ("message-width", "chatSettingsMessageWidth", "chatSettingsMessageWidthDetail"), ("message-text-size", "chatSettingsTextSize", "settingsIndexChatMessageTextSizeDetail"),
                ("line-spacing", "chatSettingsLineSpacing", "settingsIndexChatLineSpacingDetail"), ("message-spacing", "chatSettingsMessageSpacing", "chatSettingsMessageSpacingDetail"),
                ("surfaces", "chatSettingsSurfaces", "chatSettingsSurfacesDetail"),
            ])
        case .sessions:
            return page(.sessions, "new-sessions", "sessionsSettingsNewSessions", [("starts-with", "sessionsSettingsStartsWith", "sessionsSettingsStartsWithDetail"), ("work-in", "sessionsSettingsWorkIn", "sessionsSettingsWorkInDetail"),
                ("start-from", "sessionsSettingsStartFrom", "settingsIndexSessionsStartFromDetail")])
                + page(.sessions, "idle-sessions", "sessionsSettingsIdleSessions", [
                    ("sleep-after", "sessionsSettingsSleepAfter", "settingsIndexSessionsSleepAfterDetail"),
                ], keywords: ["sleep-after": "settingsIndexSessionsSleepAfterKeywords"]) + page(.sessions, "archive-and-delete", "sessionsSettingsArchiveAndDelete", [
                    ("archive-after", "sessionsSettingsArchiveAfter", "sessionsSettingsArchiveAfterDetail"), ("delete-after", "sessionsSettingsDeleteAfter", "sessionsSettingsDeleteAfterDetail"),
                    ("ask-before-deleting-a-session", "sessionsSettingsAskBeforeDeleting", "sessionsSettingsAskBeforeDeletingDetail"),
                ]) + page(.sessions, "with-these-ages", "sessionsSettingsWithTheseAges", [("with-these-ages", "sessionsSettingsWithTheseAges", "settingsIndexSessionsWithTheseAgesDetail")])
        case .projects:
            // the list and each project's screen are per-project, so their rows are not statically indexed: the page is found by its name and its line
            return []
        case .sidebar:
            return page(.sidebar, "order", "sidebarSettingsOrder", [
                ("group-epics-by", "sidebarGroupEpicsBy", "sidebarSettingsGroupEpicsByDetail"), ("sort-sessions", "sessionsSort", "sidebarSettingsSortSessionsDetail"),
                ("sort-the-archive", "sidebarSettingsSortArchive", "sidebarSettingsSortArchiveDetail"),
            ]) + page(.sidebar, "session-rows", "sidebarSettingsSessionRows", [
                ("project-icon", "sidebarSettingsProjectIcon", "sidebarSettingsProjectIconDetail"), ("branch", "sidebarSettingsBranch", "sidebarSettingsBranchDetail"),
                ("pull-request", "sidebarSettingsPullRequest", "settingsIndexSidebarPullRequestDetail"), ("lines-changed", "sidebarSettingsLinesChanged", "settingsIndexSidebarLinesChangedDetail"),
                ("providers", "sidebarSettingsProviders", "sidebarSettingsProvidersDetail"), ("age", "sidebarSettingsAge", "settingsIndexSidebarAgeDetail"),
            ])
        case .terminal:
            return page(.terminal, "appearance", "terminalSettingsAppearance", [
                ("theme", "terminalSettingsTheme", "terminalSettingsThemeDetail"), ("minimum-contrast", "terminalSettingsContrast", "settingsIndexTerminalMinimumContrastDetail"),
                ("horizontal-padding", "terminalSettingsPaddingX", "settingsIndexTerminalHorizontalPaddingDetail"), ("vertical-padding", "terminalSettingsPaddingY", "settingsIndexTerminalVerticalPaddingDetail"),
            ]) + page(.terminal, "typography", "terminalSettingsTypography", [
                ("font", "terminalSettingsFont", "terminalSettingsFontDetail"), ("size", "terminalSettingsSize", "terminalSettingsSizeDetail"),
                ("ligatures", "terminalSettingsLigatures", "terminalSettingsLigaturesDetail"), ("thicken-font", "terminalSettingsThicken", "terminalSettingsThickenDetail"),
            ]) + page(.terminal, "cursor", "terminalSettingsCursor", [("cursor-style", "terminalSettingsCursorStyle", "terminalSettingsCursorStyleDetail"), ("blink-cursor", "terminalSettingsBlink", "terminalSettingsBlinkDetail")])
                + page(.terminal, "panes", "terminalSettingsPanes", [
                    ("dim-inactive-panes", "terminalSettingsDim", "terminalSettingsDimDetail"),
                    ("focus-follows-mouse", "terminalSettingsFocusFollows", "terminalSettingsFocusFollowsDetail"),
                ]) + page(.terminal, "input-and-scrollback", "terminalSettingsInput", [
                    ("option-as-alt", "terminalSettingsOptionAsAlt", "terminalSettingsOptionAsAltDetail"),
                    ("copy-on-select", "terminalSettingsCopyOnSelect", "terminalSettingsCopyOnSelectDetail"), ("scrollback-limit", "terminalSettingsScrollback", "terminalSettingsScrollbackDetail"),
                ]) + page(.terminal, "shell-and-closing", "terminalSettingsShell", [
                    ("pin-zsh-prompt-to-bottom", "terminalSettingsPinPrompt", "terminalSettingsPinPromptDetail"),
                    ("confirm-before-closing-running-commands", "terminalSettingsConfirm", "terminalSettingsConfirmDetail"),
                ])
        case .roles:
            // the rows of a role's screen are the same for the three roles: the search opens the Author's, and the Lead reviewer's switch opens its own
            let role = [AgentRole.author.rawValue]
            // the rows of the rail: the extra reviewers are listed whether or not the file has them, since the index does not read it
            let railSlots: [RoleSlot] = [.author, .reviewer] + RoleSlot.extraPositions.map { .extra($0) } + [.lead]
            var entries = given(.roles, "how-an-epic-runs", words("rolesRailGroup"), railSlots.map { ($0.name, $0.title(bundle: bundle, locale: locale), $0.purpose(bundle: bundle, locale: locale)) })
            entries += page(.roles, "", "", [("use-a-lead-reviewer", "rolesUseLead", "settingsIndexRolesUseALeadReviewerDetail")], path: [AgentRole.leadReviewer.rawValue])
            entries += page(.roles, "who", "rolesGroupWho", [("identity", "rolesIdentity", "settingsIndexRolesIdentityDetail"), ("model", "rolesModel", "settingsIndexRolesModelDetail")], path: role)
            entries += page(.roles, "persona", "rolesGroupPersona", [("persona-name", "rolesPersonaName", "rolesPersonaNameDetail"), ("persona-prompt", "rolesPersonaPrompt", "rolesPersonaPromptDetail")], path: role)
            for skillRole in AgentRole.allCases {
                entries += skillRole.stages(bundle: bundle, locale: locale).map { stage in
                    SettingsEntry(
                        page: .roles, groupID: "skills", group: words("rolesGroupSkills"), rowID: stage.id, title: stage.title,
                        detail: Copy.settingsIndexRoleStage(detail: stage.detail, skill: stage.skill, bundle: bundle, locale: locale), path: [skillRole.rawValue],
                        copyKeys: ["rolesGroupSkills", "settingsIndexRoleStage"])
                }
            }
            entries += page(.roles, "when-it-runs-out-of-tokens", "rolesGroupTokens", [("switch-automatically", "rolesSwitch", "rolesSwitchDetail")], path: role)
            return entries
        case .identities:
            return page(.identities, "who-signs", "identitiesGroupWho", [("who-signs", "identitiesGroupWho", "settingsPageIdentitiesDetail"), ("create-a-bot", "identitiesCreateBotTitle", "settingsIndexIdentitiesCreateABotDetail")])
                + page(.identities, "signs-as", "identitiesGroupSignsAs", [("signs-as", "identitiesGroupSignsAs", "settingsIndexIdentitiesSignsAsDetail")])
                + page(.identities, "can-sign-in", "identitiesGroupCanSign", [("can-sign-in", "identitiesGroupCanSign", "settingsIndexIdentitiesCanSignInDetail")])
                + page(.identities, "open-on-github", "", [("open-on-github", "identitiesOpenOnGitHub", "identitiesOpenOnGitHubDetail")])
        case .watching:
            return page(.watching, "repositories", "watchingGroupRepositories", [("repositories", "watchingGroupRepositories", "settingsPageWatchingDetail")])
                + page(.watching, "status", "watchingGroupStatus", [("epics", "watchingEpics", "settingsIndexWatchingEpicsDetail"), ("last-check", "watchingLastCheck", "settingsIndexWatchingLastCheckDetail")])
                + page(.watching, "ready-for-carrier", "watchingGroupReady", [("ready-for-carrier", "watchingGroupReady", "settingsIndexWatchingReadyForCarrierDetail")])
                + page(.watching, "who-works-here", "watchingGroupWho", [("who-works-here", "watchingGroupWho", "settingsIndexWatchingWhoWorksHereDetail")])
                + page(.watching, "repository", "watchingGroupRepository", [
                    ("project", "watchingProject", "settingsIndexWatchingProjectDetail"), ("clone", "watchingClone", "settingsIndexWatchingCloneDetail"), ("on-github", "watchingOnGitHub", "settingsIndexWatchingOnGithubDetail"),
                ])
                + page(.watching, "stop-watching", "watchingStopTitle", [("stop-watching", "watchingStopTitle", "settingsIndexWatchingStopWatchingDetail")])
        case .behavior:
            return behaviorGroups(bundle: bundle, locale: locale).flatMap { group in given(.behavior, group.id, group.title, group.rows.map { ($0.key, $0.title, $0.detail) }) }
        case .engine:
            return page(.engine, "starting", "engineGroupStarting", [
                ("startOnOpen", "engineStartOnOpenTitle", "engineStartOnOpenDetail"),
                ("confirmStop", "engineConfirmStopTitle", "engineConfirmStopDetail"),
            ]) + page(.engine, "programs", "engineGroupPrograms", [
                ("carrier", "settingsIndexEngineCarrierTitle", "settingsIndexEngineCarrierDetail"), ("node", "settingsIndexEngineNodeTitle", "settingsIndexEngineNodeDetail"), ("path", "settingsIndexEnginePathTitle", "settingsIndexEnginePathDetail"),
                ("lookAgain", "engineLookAgainTitle", "settingsIndexEngineLookAgainDetail"),
            ]) + page(.engine, "github-identity", "engineGroupGitHub", [("orchestratorProfile", "engineProfileTitle", "settingsIndexEngineOrchestratorProfileDetail")])
                + page(.engine, "files", "engineGroupFiles", [
                    ("carrierFolder", "engineFolderTitle", "engineFolderDetail"), ("logs", "engineLogsTitle", "engineLogsDetail"),
                    ("startLog", "engineStartLogTitle", "engineStartLogDetail"),
                ])
        case .health:
            return page(.health, "this-mac", "healthThisMac", [("this-mac", "healthThisMac", "settingsIndexHealthThisMacDetail")])
                + page(.health, "carrier", "appName", [("chat-host", "healthChatHost", "settingsIndexHealthChatHostDetail"), ("engine", "healthEngine", "settingsIndexHealthEngineDetail")])
                + page(.health, "engine-setup", "healthEngineSetup", [("engine-setup", "healthEngineSetup", "settingsIndexHealthEngineSetupDetail")])
        case .about:
            return page(.about, "about", "aboutGroupAbout", [("star-carrier-on-github", "aboutStarTitle", "aboutStarDetail")])
                + page(.about, "updates", "aboutGroupUpdates", [
                    ("check-by-itself", "aboutRowCheck", "aboutRowCheckDetail"),
                    ("install-by-itself", "aboutRowInstall", "aboutRowInstallDetail"), ("update-delay", "aboutRowDelay", "settingsIndexAboutUpdateDelayDetail"),
                ]) + page(.about, "engine", "aboutGroupEngine", [("engine-and-chat-host", "aboutRowEngine", "settingsIndexAboutEngineAndChatHostDetail")])
        }
    }
}

/// The places that match `query`, best first: every word of it has to be in the title, the group, the page, the description or the keywords (case
/// and accents ignored); a match in the title goes before one in the group or the page, and that before one in the description. The same rank keeps
/// the order of the sidebar and of the page. The page's name is read in the language of `bundle` and `locale`, the one the entries were built in.
public func settingsResults(_ query: String, in entries: [SettingsEntry] = settingsIndex, bundle: Bundle? = nil, locale: Locale = .current) -> [SettingsEntry] {
    func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
    let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    guard words.isEmpty == false else { return [] }
    func rank(_ entry: SettingsEntry) -> Int? {
        let title = fold(entry.title), place = fold(entry.group + " " + entry.page.title(bundle: bundle, locale: locale)), detail = fold(entry.detail + " " + entry.keywords)
        guard words.allSatisfy({ title.contains($0) || place.contains($0) || detail.contains($0) }) else { return nil }
        if words.allSatisfy({ title.contains($0) }) { return 0 }
        if words.allSatisfy({ title.contains($0) || place.contains($0) }) { return 1 }
        return 2
    }
    return entries.enumerated().compactMap { index, entry in rank(entry).map { (rank: $0, index: index, entry: entry) } }
        .sorted { ($0.rank, $0.index) < ($1.rank, $1.index) }.map(\.entry)
}
