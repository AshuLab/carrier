# Global dictation

Status: spec
Source: AshuLab/carrier#983

## Problem

The owner dictates today with an external app, FluidVoice, because Carrier's dictation only works inside its own message boxes: it needs Carrier's window in front and a click on the microphone. [0023](../adr/0023-dictation-runs-on-recognizers-with-a-fixed-list-of-downloadable-speech-models.md) built the recognizers and the core so that this could stop, and left the global dictation for its own epic.

It is solved when he can uninstall FluidVoice: one global shortcut, from any app, that takes what he says and puts it in the text field where his cursor is, as a toggle or as a hold, with the recognizers he already has. Nothing is kept of what he says today, and he wants more than parity: to look back at what he dictated, to see how much he uses it, to have a model clean the text before it lands (filler words, translation, a more technical tone), and a better look for the dictation in Carrier's own box.

## Solution

One shortcut, configurable, and the app decides by where the person is ([0029](../adr/0029-global-dictation-is-a-widget-that-pastes-once-and-falls-back-to-the-clipboard.md)). With Carrier in front on a session, it focuses the message box and dictates into it exactly as today, with no widget. Anywhere else, Settings and the epic views of Carrier included, it opens a floating widget that does not take the focus from the app the person is in, on the display of the active window. The widget shows the text as it is said, read only, and pastes it once at the end into the field with the cursor. If no field has the cursor, or the Accessibility permission is missing, the text stays in the widget and is also on the clipboard, so a dictation is never lost; it is never pasted into a secure field (a password), and the widget says so. Escape cancels and pastes nothing. A dictation with no words pastes nothing and closes without a trace. The activation is a toggle (the shortcut starts and the next press ends) or a hold (it listens while the keys are down), set on the Dictation page. A cleaned or raw text is pasted with the clipboard put back as the person had it, which the spike below has to prove possible.

The widget is the message box, floating. It is glass, takes its colours from the app's accent, and while it listens it draws the same line as the message box (`DictationIndicator`): a ring outside the edge in the accent and two hues turned 40 degrees each way, a bright arc with a bloom that goes round, the voice setting its speed, its width and its tremble, a slow breath in silence, and the Reduce Motion and Reduce Transparency rules of the box. The line exists only while it listens. What the widget holds while it listens is the text, the time, the shortcut and Esc: no label, no pulsing dot, no waveform. The text starts at the top of the box and goes down like in any text field; the box has one height per style, and when the text reaches the bottom it scrolls, the newest words on the last line and the older lines fading out at the top. There are four styles, chosen in Settings: Pill, a badge with a microphone and no text, with the same glow and an icon that follows the state (a spinner while it works, a sparkle while it cleans, a check when pasted, a warning when it pasted without cleaning, an x when cancelled); and Small, Medium and Large, the box at 2, 3 and 4 lines and 340, 420 and 540 points, with 12, 14 and 17 point text. The position is Top or Bottom of the screen. The states that need text or a button (no text field, Accessibility off, could not start) open the Pill as the Small box until they are dismissed; in those the text is complete and scrolls, with Copy and Dismiss. Pasted fades by itself.

The cleanup is one prompt, written in a text box in Settings with a sensible default that removes filler words, applied to the text when the dictation ends by a local model server, LM Studio or Ollama, through its API with no tools, in the widget and in the message boxes alike ([0030](../adr/0030-dictation-cleanup-runs-on-local-model-servers-through-their-api.md)). While it works the widget shimmers over the raw text and the box says Cleaning…; Esc skips it and uses the raw text; a failure or a timeout uses the raw text and says why. It is off until the person picks a server and a model.

The history keeps one entry per dictation with the text as recognized and as cleaned, the speech model, the time the transcription took, the cleanup model and its time, the audio length, the words, where it went and how it ended, cancelled and failed included ([0031](../adr/0031-dictation-keeps-a-history-and-its-statistics-live-apart-from-it.md)). Keeping the text is on by default; keeping the audio is off, with a limit in days (30 by default), a Delete all audio that keeps the transcripts, and an entry deleted taking its audio with it. The statistics are counters of their own, per day and hour, written when a dictation ends whatever the history says, with Reset statistics; the time saved is computed from the typing speed setting (40 words a minute by default).

The Dictation page of Settings gets three segments, General, History and Statistics, drawn in the prototype ([global-dictation-prototype.html](../research/macos-app-design/explorations/global-dictation-prototype.html)). General holds Dictation (the master switch: off, it turns the global dictation off too), Global dictation (Dictate in any app, the shortcut recorder, toggle or hold, the state of Accessibility, Widget style, Position and a live preview), Sounds (a start sound and an end sound, each on or off and chosen among a few of the system's, and one volume), Cleanup (server, model, the prompt and a Test) and the Speech models table as it is. History starts with its settings (keep the text, keep the audio, delete audio older than, Delete all audio) and then the list: search, filters by outcome, day groups, and rows that open to the detail, copy the text, delete, and play the audio when kept. Statistics shows a range (7, 30, 90 days or all), the dictations, words, speaking time and time saved, a chart by day of words or dictations, the hours of the day, a weekly summary and the records (most dictations and most words in a day, the longest dictation, the longest streak), and ends with its settings: the typing speed and Reset statistics. The first time the person turns on Dictate in any app the page explains what Accessibility is for and then asks macOS.

Whether it is the first cut or later, every slice updates `docs/macos/dictation.md`, `macos/AGENTS.md` and the CHANGELOG, which are this repo's record of what the person sees and where the code lives.

## Scope

The global core and the widget:

1. A person presses the global shortcut in any app and a widget opens without taking the focus from the app they are in, on the display of the active window.
2. A person sees the text as they say it, with the time, the shortcut and Esc, and ends the dictation with the same shortcut (toggle) or by releasing it (hold), and the text is pasted once into the field with the cursor.
3. A person chooses between toggle and hold on the Dictation page.
4. A person presses Esc and nothing is pasted, nothing is left on the clipboard and the widget closes.
5. When no text field has the cursor, the text stays in the widget, complete and scrollable, with Copy and Dismiss, and is also on the clipboard.
6. When the Accessibility permission is missing, the text is copied and the widget says so, with Open System Settings.
7. The text is never pasted into a secure field, and the widget says why.
8. With Carrier in front on a session, the shortcut focuses the message box and dictates into it as today, with no widget; in any other view of Carrier it uses the widget.
9. A person records the shortcut in Settings, which starts at ⌥⇧ Space (⌥ Space is held by ChatGPT and Handy, see the [input spike](../research/global-dictation-input.md)) and refuses a combination with no modifier.
10. A person turns on Dictate in any app, is told what Accessibility is for before macOS asks, and the Dictation switch off turns the global dictation off too.
11. A person chooses the Widget style (Pill, Small, Medium, Large) and the Position (Top, Bottom), and sees a preview in Settings.
12. The widget is glass in the app's accent, draws the message box's listening line only while it listens, and its text starts at the top, goes down and scrolls with the older lines fading at the top.
13. The Pill shows an icon for each state and opens as the Small box for the states that need text or a button.
14. A person hears a start sound and an end sound, each on or off, chosen among a few of the system's, at one volume they set.
15. A failure to start or to recognize shows its cause in the widget and is appended to `dictation.log`.
16. A dictation with no words pastes nothing and closes quietly, and is not recorded.

The cleanup:

17. A person turns on Cleanup, picks LM Studio or Ollama, picks one of the models that server lists, writes the prompt (it starts with a default that removes filler words) and tries it with Test.
18. With Cleanup on, the text goes through the model when the dictation ends, the widget shows that it is cleaning, Esc skips it, and the result is what is pasted.
19. The same cleanup runs in the message boxes, which say Cleaning… before the result.
20. If the server is down, the model is missing or the call times out, the raw text is used, the widget or the box says it could not be cleaned, and the cause goes to `dictation.log`.
21. Cleanup does nothing until a server and a model are chosen.

The history:

22. Each dictation is recorded with its fields when keeping the text is on, cancelled and failed ones included, and nothing new is recorded when it is off.
23. A person sees the History segment with its settings on top: keep the text, keep the audio, delete audio older than N days (30 by default) and Delete all audio.
24. A person browses the entries grouped by day, searches them, filters by outcome, opens one for its detail, copies its text, deletes it and plays its audio when it was kept.
25. Audio is saved only when the setting is on; the old audio is deleted by the limit of days; Delete all audio keeps every transcript; deleting an entry deletes its audio.

The statistics:

26. The counters are written when each dictation ends, whatever the history settings are, and hold no text.
27. A person sees the Statistics segment: the range, the four figures, the chart by day, the hours of the day, the weekly summary and the records.
28. A person sets the typing speed (40 words a minute by default) and the time saved follows it.
29. A person resets the statistics after a confirmation, and the history is not touched.

The message box:

30. The message box gets a new visual effect while it dictates, besides the line it has. Blocked on the reference the owner will share.

## Decisions

The shortcut is a system hot key, which is expected to need no permission; the Accessibility permission is asked only to see what has the focus and to paste ([0029](../adr/0029-global-dictation-is-a-widget-that-pastes-once-and-falls-back-to-the-clipboard.md)). The cleanup client speaks one dialect to both servers: `/v1/models` to list and `/v1/chat/completions` to clean, which LM Studio and Ollama both serve on their local ports, with a timeout and no tools ([0030](../adr/0030-dictation-cleanup-runs-on-local-model-servers-through-their-api.md)). The history is a JSON Lines file of entries and a JSON file of counters in `<Carrier folder>/app/`, read into memory and filtered there, with the audio as files next to them referenced by entry id ([0031](../adr/0031-dictation-keeps-a-history-and-its-statistics-live-apart-from-it.md)); this is the smallest thing that holds a few thousand entries, and a move to SQLite is for when the list is slow. New preferences are keys of `AppPreferences` under the Dictation page, and `reset(.dictation)` puts them back to their defaults without touching the history or the statistics.

The rule for where a dictation goes is a pure function of what the system says about the focus and the permission, so it can be tested without a screen:

```swift
enum FocusedElement { case editable, secure, none }
enum PasteReason { case noField, noPermission, secureField }
enum PasteDecision: Equatable { case paste, copyOnly(PasteReason) }

/// `focus` is nil when it could not be read, which is what an app without the permission gets.
func pasteDecision(focus: FocusedElement?, trusted: Bool) -> PasteDecision {
    guard trusted, let focus else { return .copyOnly(.noPermission) }
    switch focus {
    case .editable: return .paste
    case .secure: return .copyOnly(.secureField)
    case .none: return .copyOnly(.noField)
    }
}
```

The time saved is the words over the typing speed, minus the time spent speaking, and never negative or a division by zero:

```swift
func timeSaved(words: Int, speaking: Duration, wpm: Int) -> Duration {
    guard words > 0, wpm > 0 else { return .zero }
    return max(.zero, .seconds(Double(words) / Double(wpm) * 60) - speaking)
}
```

Testing seams, chosen as the broadest that still isolates each story, on the seams this repo already has (`CarrierCoreTests`, with the scripted recognizer and capture of `ScriptedDictation.swift` and the fake clock of `DictationSessionTests`):

- Stories 2, 3, 4, 16 (toggle, hold, Esc, empty): a new `GlobalDictation` state machine in `CarrierCore`, fed key events (down, up, Esc) and the scripted recognizer, observed through its state and what it asks the outside to do (paste, copy, close). Tap and hold, a hold shorter than the recognizer's first text, and Esc in each state are cases of this one seam.
- Stories 5, 6, 7: `pasteDecision`, as above, and the same machine's output for each decision. The Accessibility and clipboard code that carries them out has no automated test and is covered by the spike.
- Story 8: the routing rule (Carrier in front on a session, or not) as a pure function of the front window, tested alone; the message box side is `MessageBoxDictationTests` in `CarrierTests`.
- Stories 9, 10, 11, 14, 23, 28: `AppPreferences` keys with their defaults and `reset(.dictation)` in `AppPreferencesTests`, and the rows and their dimming in `SettingsPageTests` and `DictationSettingsTests`, as the page's other rows are tested.
- Stories 12 and 13: a pure function from the dictation state, the style and the text to what the widget draws (the lines, which icon, whether the Pill opens as Small, whether it fades), next to `dictationPresentation` in `DictationPresentationTests`. The window, the glass and the line are looked at in the app, not tested, with the procedure of `macos-ui-change`.
- Story 15: `DictationLogTests`, as failures are tested today.
- Stories 17 to 21: a `TextModelClient` port with a scripted fake and a `CleanupRun` that is given the client and the clock, in `CarrierCoreTests`: success, a server that is down, a missing model, a timeout, Esc during it, and the empty prompt. The HTTP client itself is tested against a local stub server on a real socket, as the engine's socket is.
- Stories 22, 24, 25, 26, 27, 28, 29: the history and the counters as one `DictationRecords` type over a temporary folder: record, search, filter, delete, the audio limit with a fake clock, Delete all audio, the counters surviving a delete and a history turned off, Reset, and the figures of the Statistics segment (ranges, time saved, weekly summary, records, the streak, the busiest hour) as pure functions of the counters, tested directly.
- Story 1: no automated test for the window (it does not take the focus, the display it opens on); looked at in the app.
- Story 30: no tests until the reference exists; looked at in the app.

## Out of scope

- Cleanup through cloud models. It comes later, through their APIs and not through the agent CLIs.
- Named presets of cleanup prompts and a picker for them in the widget.
- Editing the text in the widget before it is pasted.
- Typing into other apps as the words arrive.
- A personal dictionary.
- The widget landing in Carrier's message box when the person comes back mid-dictation.
- Dragging the widget, or a position other than Top and Bottom.
- An entry in the menu bar to open the history.
- Automatic retention of the text of the history; it stays until the person deletes it.

## Open questions

- Does the Accessibility permission survive a Sparkle update with the ad hoc signature of [0017](../adr/0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md)? A spike, since the fallback of the widget is built on the answer.
- Does the system hot key give the key release a hold needs, and does ⌥ Space collide with anything on the owner's Mac? A spike.
- How does the app know that a text field has the cursor in another app and that it is secure, and how does it paste without losing the person's clipboard, and where does it fail (terminals, web inputs)? A spike.
- Does a small local model clean Spanish and English mixed well enough, and is the wait between the end of the dictation and the paste short enough to use? A measurement with the models the owner has, before the cleanup slice is built.
- Is the glass legible over light backgrounds in the real app, in light and dark? Looked at in the app; the tint of the prototype is a first number.
- The new visual effect of the message box (story 30): blocked on the reference the owner has not shared yet.
