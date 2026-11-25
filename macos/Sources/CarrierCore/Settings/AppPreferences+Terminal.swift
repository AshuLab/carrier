import Foundation

extension AppPreferences {
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
}
