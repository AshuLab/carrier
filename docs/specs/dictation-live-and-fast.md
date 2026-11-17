# Dictation that is live and fast

Status: spec
Source: AshuLab/carrier#1086

## Problem

The owner recorded 27 seconds of Spanish dictated into a message box on Nemotron 3.5 Multilingual, and the dictation felt slow and rough.
The first words took several seconds to show: after five seconds of speech the box showed only "Hola,", and through the rest the text came about a word behind the voice.
The whole dictation was drawn as partial text (accent colour, dotted underline) from the first word to the last, it grew in jumps of about a second, and its punctuation was sparse.
It misheard small words: "distinto nosotros" for "distinto a nosotros", "y del texto" for "y el texto".

Reading the code explains part of it, and leaves the rest as hypotheses to measure.

- The model loads on the first dictation, and the microphone starts only after it is ready. If the recording was the first dictation since Carrier opened, the load alone explains the first seconds. Nobody has measured where the time between the press and the first word goes.
- Every partial event the recognizers send is the whole text of the dictation, so the box cannot tell the words that will not change from the ones still forming, and draws all of it as partial. The core's chunking already knows which words are settled; it does not say so.
- Nemotron 3.5 Multilingual runs on its full-vocabulary build at 1.12 s chunks, so its text grows in steps of about a second. FluidAudio also ships a build pruned to English, Spanish, French, Italian, Portuguese and German, which its docs call faster, and chunks of 0.56 s and 2.24 s.
- For Parakeet TDT v3 the core closes a segment at every pause of 150 ms below a fixed -45 dBFS and transcribes each segment on its own, so the model never sees a whole sentence, not even at the stop. [The chunked partials spike](../research/dictation-chunked-partials.md) found that this costs no wrong words (0.0%) on its clips, but it counted words only, lowercase and without punctuation, on synthetic voices with clean pauses: what it does to the punctuation, the capitals and a real voice in a real room is not known. The owner has not tried Parakeet TDT v3 in Carrier for this comparison.
- The box says "Transcribing…" at the stop however short the wait, so even a quick final text reads as a wait.

It is solved when the owner records the same dictation again, on the model of his choice, and the words show as he says them, the text is clean and punctuated, and it flows instead of jumping.

## Solution

The epic does what is cheap and certain and measures where the wait goes; what still feels slow after it is the next epic's, decided on the owner's new recording and the measurements.

**Measure the start.**
Each dictation logs, with no text, the time from the press to the capture running, to the first audio, to the model ready and to the first word shown, and the time from the stop to the final text, in `dictation.log`.
This says where the wait goes before anything else is tuned.

**The model is ready before the press.**
A new switch, Keep the speech model ready (on by default), loads the chosen model in the background when Carrier opens with Dictation on, and again when Dictation is turned on or the chosen model or language changes.
A new popup, Release the model after (5, 15, 30 or 60 minutes without dictating, or Never; 15 by default), frees the memory of a model nobody is using, whatever the switch says; the next dictation loads it again.
With the switch off a model loads at the first dictation, as today, and the release still applies.
With Dictation off nothing loads.
Apple's model is kept by the system's retention (`SpeechAnalyzer.Options.modelRetention`) while it is ready, and let go when it is released.

**The microphone never waits for the model.**
The press starts the capture at once and the audio is kept until the recognizer is ready, then given to it from the first sample, so the words said while the model gets ready are not lost.
From the press the box and the widget draw the listening line and the clock, as when they listen, with "Getting the model ready…" where the text will be until the model is ready; then the words catch up.
The start sound plays when the first audio arrives.
A stop while the model gets ready (a click, the shortcut, a release in Hold) ends the capture and keeps what was captured, which the recognizer reads once it is ready; a release right after the press in Hold still pastes nothing, as today, and Esc drops it all.

**The text has a firm part and a tentative part.**
A partial event says which of its words are firm, the ones that will not change while the person speaks, and which are tentative.
The box and the widget draw the firm words as normal text and only the tentative ones as partial text.
The core's chunking gives its settled words as firm, and Apple's final results are firm and its volatile ones tentative.
The streaming models (Nemotron, Parakeet EOU, Parakeet Unified) give every word but the last as firm: their partial text only grows, and its last word may still grow by a piece of a word ("conte" becoming "contexto").

**The stop feels instant.**
"Transcribing…" appears only when the final text takes more than 250 ms after the stop.

**The other recognizers get their cheap wins.**
Apple's transcriber drops `fastResults`, which its documentation says trades accuracy for speed.
Whisper stops asking for word timestamps when it gives its text at the end (they are not used) and lets WhisperKit cut a recording longer than 30 s at its pauses and decode the pieces in parallel (`chunkingStrategy: .vad`).
Parakeet TDT v3 and Ultra run one silent pass when they load, so the first dictation does not pay the first inference.

Every slice updates `docs/macos/dictation.md`, `macos/AGENTS.md` and the CHANGELOG.

## Scope

The start:

1. Each dictation logs, with no text, the time from the press to the capture running, to the first audio, to the model ready and to the first word, and from the stop to the final text.
2. With Keep the speech model ready on and Dictation on, the chosen model loads in the background when Carrier opens, when Dictation is turned on and when the chosen model or language changes, so the first dictation does not wait for it.
3. A model not used for the time chosen in Release the model after is released, and the next dictation loads it again; Never keeps it until Carrier quits.
4. With Keep the speech model ready off, a model loads at the first dictation, as today; with Dictation off nothing loads.
5. Both new settings are on the Dictation page, drawn at 40% with Dictation off, and `reset(.dictation)` puts them back.
6. The capture starts at the press, before the model is ready; the box and the widget draw the listening line and the clock with "Getting the model ready…", and the words said meanwhile are in the text.

The text:

7. A partial event carries its firm words and its tentative words, and every recognizer fills both by the rules above.
8. The message box and the widget draw only the tentative words as partial text; the firm ones are normal text, and the widget's scrolling keeps working.
9. "Transcribing…" shows only when the final text takes more than 250 ms.

The cheap wins:

10. Apple's transcriber runs without `fastResults` and keeps its model by retention while it is ready.
11. Whisper runs without word timestamps when it gives its text at the end, and with WhisperKit's cutting at pauses for recordings over 30 s.
12. Parakeet TDT v3 and Ultra warm up with one silent pass when they load.

## Decisions

The event that carries the text changes from one string to two:

```swift
public enum DictationEvent: Sendable, Equatable {
    /// `firm` will not change while the person speaks; `tentative` follows it and may.
    case partial(firm: String, tentative: String)
    case final(String)
    case failed(DictationFailure)
}
```

`TentativeText` keeps one range for the dictation's text and a split inside it, so the box draws only the tail as partial.

The release is a new requirement of the `Recognizer` port, `release()`, which drops what `prepare` loaded; the timer that calls it lives in `DictationController`, from the end of the last dictation, on an injected clock.
The capture that starts before the model is a buffer in `DictationSession` between `capture.start()` and `recognizer.recognize`.
A model that takes longer than the session's answer floor (30 s) to get ready with the capture running fails as a dictation that could not start, with what was heard dropped, so a first load that compiles for minutes does not record for minutes.

The model the person dictates with is the person's choice: the app suggests none, and the default stays as it is.

The rule for the streaming models comes from FluidAudio 0.18.3: Nemotron and Parakeet EOU decode all the tokens they have accumulated, which only grow (`StreamingNemotronAsrManager+Pipeline.swift`, `StreamingEouAsrManager.swift`); Nemotron 3.5 Multilingual publishes only the tokens its blank rescue has settled (`publishPartialTranscript`); and Parakeet Unified rewrites earlier words only with vocabulary boosting, which Carrier does not configure.
A FluidAudio update re-reads them.

Testing seams, on the ones the repo has (`CarrierCoreTests` with the scripted recognizer and capture of `ScriptedDictation.swift` and the fake clock of `DictationSessionTests`):

- Story 1: `DictationSessionTests` with the fake clock, asserting the times handed to the log, and `DictationLogTests` for what is written, with no text.
- Stories 2, 3, 4, 5: the ready and release rule as a pure function of the switches, the popup, the last dictation and the clock, tested alone; the preferences in `AppPreferencesTests`, the rows and their dimming in `DictationSettingsTests`.
- Story 6: `DictationSessionTests` with a recognizer whose `prepare` waits on a signal, asserting that the audio captured before it is the first audio the recognizer reads, and the failure past the floor; `DictationPresentationTests` for what is drawn meanwhile.
- Story 7: each recognizer's mapping to firm and tentative, in `ChunkedPartialsTests`, `AppleRecognizerTests`, `FluidAudioRecognizerTests` and `FixtureRecognizerTests`.
- Story 8: `TentativeTextTests` for the split, `MessageBoxDictationTests` for what the box draws; the widget with the procedure of `macos-ui-change`.
- Story 9: `DictationPresentationTests` with the fake clock.
- Stories 10, 11 and 12: no tests, as the recognizers' options are not tested today; looked at in the app.

## Out of scope

- Nemotron 3.5 Multilingual's pruned build and its other chunk sizes.
- Keeping the audio engine prepared between dictations and tapping it in smaller blocks.
- Parakeet TDT v3 over whole sentences: transcribing the open window every half second, words made firm by agreement, commits at sentences, and a final pass over the whole audio that may correct what was shown. It needs a measurement of punctuation, capitals and energy on the owner's voice first.
- These three wait for the owner to record the same dictation again with this epic shipped; if it still falls short, they are the next epic, with the start's times from the log to say where.
- Removing filler words, a dictionary of replacements and spoken punctuation without a language model: the next epic.
- Vocabulary boosting for any recognizer.
- Suggesting a speech model to the person.
- A fade of the new words: looked at again once the text is firm and tentative, if it still reads as jumping.
- Capturing through Core Audio directly instead of `AVAudioEngine`.
- Partial text by segments for the models that give their text at the end.
- A second model that corrects a streaming model's text at the stop.

## Open questions

- Should the Speech models table say how much memory each model holds while it is ready? The slice of story 2 measures it either way.
