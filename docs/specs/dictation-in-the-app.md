# Dictation in the app

Status: implemented (v0.4.0)

Source: AshuLab/carrier#856

## Problem

Carrier has no voice input. A person who wants to dictate a prompt into the chat has to use another app: the owner does it today with FluidVoice, on Parakeet TDT v3, in a mix of Spanish and English, and it works for him, including text that appears while he speaks. What hurts is not that dictation is impossible but that it lives outside the product: it is a second tool to install, set up and keep, and a person who uses Carrier without one has no dictation at all. Dictation is also cheap to build now that the app targets macOS 26 and the recognizers run on the Mac, so it is value added to the product, not a repair.

It is felt first by the owner, who wants to stop using the external app, and then by anyone who uses Carrier and would speak a prompt; the feature has to be generic, not shaped by how one person dictates. We know it is solved when a person can press a button in the chat composer, speak, and see text appear in the field while they speak; when they can choose the recognizer and, from a list, the model they want, and download it from the app; when the owner finds the result as good as his external app on the same speech; and when a shortcut, dictation into other apps, cleanup with a language model and a personal dictionary can be added later on the same core without cutting it open.

Said plainly, this cut alone does not let the owner switch the external app off, because that app also dictates outside Carrier. It is the first step of that, and the core is built for the rest.

## Solution

The app listens through the microphone from an icon in the message box and writes what it hears into the field, with recognizers that run on the Mac; and a Dictation page in Settings lets a person choose the recognizer, the model and the language, and download the models. The logic lives in `CarrierCore` behind one boundary, a recognizer, and [0023](../adr/0023-dictation-runs-on-recognizers-with-a-fixed-list-of-downloadable-speech-models.md) records the structure, the licences and the alternatives that lost.

There are three recognizers: Apple's SpeechAnalyzer, which needs no download because the system manages its assets; FluidAudio, which runs Parakeet and Nemotron on Core ML (Apache-2.0); and WhisperKit, which runs Whisper on Core ML (MIT). Each offers a list of speech models. The person picks a model, and so a recognizer, and a language.

The speech models are one list fixed in the app's code, shown whole on one page and filterable by recognizer. Each entry has its recognizer, name, size, languages, whether it detects the language, how it gives partial text, its licence and a link to its card. Nothing outside the list can be downloaded, and nothing in it ships with the app. The list is the speech recognition models of FluidAudio's `Models.md` at the pinned version, and four of WhisperKit's Whisper models (tiny, base, small and the quantized large v3 turbo), minus any that fails the catalog check: the model loads from its folder and turns a short clip of speech into text that is not empty, and its licence is recorded. At the time of writing FluidAudio offers Parakeet TDT v3 (25 languages, CC-BY-4.0), Parakeet EOU 120M and Nemotron Streaming EN (English only, NVIDIA Open Model License), Nemotron 3.5 Multilingual (English, Spanish, French, Italian, Portuguese, German, Chinese and Japanese, OpenMDW-1.1), and the Parakeet Ultra and Unified models its documentation lists, whose size and fitness the check settles.

Partial text, the words shown while the person still speaks, comes in three ways, one per model. A recognizer that streams (Apple, Nemotron, Parakeet EOU) gives it natively. A model that is fast but does not stream (Parakeet TDT v3, the small Whisper models) gets it from the core, which transcribes the audio so far at short intervals, the way FluidVoice and Handy do; how often it does and which words it holds as settled is the second open question below. A model too slow for that (the large Whisper) gives its text when the person stops, and the box says it is transcribing. Whisper goes through WhisperKit's plain transcription with the core's own chunking, not through WhisperKit's streaming transcriber, so that the three recognizers share one way of making partial text.

A model is downloaded only by an explicit action of the person, from the page, with the downloaders of FluidAudio and WhisperKit (which resume, retry and report progress) aimed at `<Carrier folder>/app/models/<recognizer>/<model>/`. The app owns that subfolder as the engine owns `engine/` and the chat `chat/` ([0016](../adr/0016-carrier-keeps-everything-in-one-folder-with-a-subfolder-per-process.md)). Both libraries are told never to fetch when they load a model, so loading is offline and nothing is ever downloaded unasked; a library that finds a damaged folder fails with its cause instead of downloading again. A partial file left by an app that quit mid-download is deleted at the next launch. A model that is in use has no delete, and a failed download says why: no connection, no space on the disk, a file that did not check.

Dictation is on by default and works from the first click with Apple's recognizer, with nothing to download. The first click asks macOS for the microphone. The default stays Apple's whatever the result in Spanish: a person who finds it weak chooses another model and configures it, and the app downloads nothing for them.

The language is chosen in a selector that is always on the page. It offers Automatic where the model detects the language (Parakeet TDT v3, Nemotron 3.5 Multilingual and Whisper do, which is what lets a person mix Spanish and English) and the languages the model understands otherwise. A model that is English only offers English. Apple's takes one language, so it starts on the first language of macOS that it supports and the page says why Automatic is not there. A saved language that the chosen model does not offer falls back to the first it does.

The page follows `docs/research/macos-app-design/explorations/dictation-settings-spec.html`, which draws it with the real tokens of Settings and carries the guide to build it: what is reused, what is new, the states and the accessibility. The three layouts that were compared, with the ones that lost and why, are in `dictation-settings-options.html`. It is the Dictation page of the App group, after Chat, because it configures this Mac and not Carrier's engine or its chat. Its first row is the switch. Under it are the speech model (a popup of the downloaded ones), the language and the microphone's state, then the models table with the recognizer filter, then Storage, then Reset. With the switch off, the rows under it and the table are drawn at 40% and take no clicks; Storage and Reset stay live so the disk can be freed. Off removes the microphone from the message box, asks macOS for nothing and never listens; what was downloaded stays. The choices, which are the switch, the model and the language, are the app's preferences in user defaults, and Reset puts the page back to on, Apple and the language of macOS without deleting a download.

The icon is a `mic` with no button shape in the message box, to the left of Send, in the new-session view and in the open conversation, which share the box; with the switch off it is not drawn at all, not drawn dimmed. A click starts listening and the next click stops it; a typed key and Enter stop it too, and Escape cancels it: the audio is dropped and the text already on the screen stays. The text goes in at the caret (with a space before it when it follows a word), in the normal colour with a touch of the accent and a dotted underline while it is partial and plain when it is final, so the guess is not told by colour alone; and the text that was already in the box is not touched. A key the person types ends the listening and keeps what was heard, so the box never has two writers. Enter ends the listening and does not send: Send is disabled while it listens, and a second Enter sends. Only one dictation runs at a time: starting another, in another session or window, stops the first and keeps its text. Switching session, closing the window, sending the app to the background and turning the switch off also stop it and keep what was heard; none is a gesture to stop but a rule so that nothing records unseen.

While it listens nothing is written in words. A line rests on the box's edge, outside it and never over the text: a dim ring of the accent and two neighbouring hues and, over it, a bright arc with a short bloom that always goes round, slowly in silence and faster, thicker and trembling with the mids and highs of the voice; the icon fills with the same level. Reduce Transparency keeps only the ring, and Reduce Motion stops the turn and the tremble and lets the brightness follow the voice. The two states in which a spinner cannot say what is awaited keep a short caption in the bottom row: "Getting the model ready…" (the first load of a model, or Apple fetching the assets of a language) and "Transcribing…" (after stopping with a model that gives its text at the end). A microphone that macOS blocks shows `mic.slash`, and a click opens a popover with Open System Settings. A failure to start shows its cause in red under the box, as a refused send does. The icon, the indicator that was chosen among three, the three levels of light and the guide to build all of it are in `docs/research/macos-app-design/explorations/dictation-composer-spec.html`.

The level comes from the audio capture, which every recognizer shares, so it is computed once: the root mean square of each buffer, in decibels, with a floor and a ceiling, smoothed so that it rises faster than it falls, about thirty times a second, in three bands (low, mid, high) as well. The line's width, speed, opacity and tremble follow it. The audio is held in memory only and dropped when the listening ends: it is never written to disk and never leaves the Mac.

A failure to start, to load a model or to download is logged with its cause in `<Carrier folder>/app/logs/dictation.log`, never with the audio or the text. What the person caused (a denied microphone, no connection, a full disk) is told in plain words and is not a bug; what nobody expected carries its cause in the message and in the log.

For the build, the app's `Info.plist` gains `NSMicrophoneUsageDescription`, and `build-app.sh` fails without it as it does for a missing icon; `NSSpeechRecognitionUsageDescription` joins it only if the first open question says Apple's recognizer needs it. FluidAudio and WhisperKit are pinned with `exact:`, as Sparkle is. `THIRD-PARTY-NOTICES.md` lists the two libraries with their licences and the models as downloaded by the person and not bundled, each with its licence, in the pattern the file already has; the glossary's Carrier folder entry and the macOS README gain the `app/` folder and the feature.

## Scope

1. A dictation turns audio into text events through one recognizer boundary, and a scripted recognizer and a scripted capture drive a whole dictation with no audio of the Mac and no model.
2. A dictation goes from idle to getting ready, listening, transcribing where it applies, and back to idle; a failure at any point returns to idle with its cause and keeps the text heard so far.
3. Only one dictation runs at a time, and a dictation that stops for any reason keeps what was heard.
4. The level of the capture is computed once for every recognizer, from the root mean square in decibels with a floor and a ceiling, smoothed so that it rises faster than it falls, about fifteen times a second.
5. Text enters the box at the caret as partial and becomes final, the text already there is not touched, a key typed ends the listening and keeps the text, and Enter ends it without sending.
6. A model that is fast and does not stream gets partial text from the core, which transcribes the audio so far at short intervals; a model too slow for it gives its text at the end.
7. The audio is held in memory only and dropped when the listening ends; nothing is written to disk or sent anywhere.
8. The speech models are one fixed list, each entry with its recognizer, size, languages, whether it detects them, how it gives partial text, its licence and a link to its card; every entry passes the catalog check, and nothing outside the list can be downloaded.
9. A person can download a model, see its progress, cancel, retry after a failure that says its cause, and delete it; a partial file is removed at the next launch, and the model in use has no delete.
10. Models live in `<Carrier folder>/app/models/<recognizer>/<model>/`, and a library never downloads when it loads a model.
11. Apple's recognizer works with no download and is the default; the first click asks macOS for the microphone, and a denied microphone says so with a way to System Settings.
12. The language selector offers Automatic only where the model detects the language, offers English only for an English-only model, starts Apple's on the language of macOS, and falls back to the first language a model offers when the saved one is not among them.
13. FluidAudio, WhisperKit and Apple's recognizer each listen and give text through the boundary, with their models loaded from the Carrier folder and offline.
14. The Dictation page is in the App group after Chat, with the switch, the speech model, the language, the microphone's state, the models table filterable by recognizer, Storage and Reset.
15. With the switch off the icon is not drawn, macOS is asked for nothing and nothing listens, the page dims under the switch except Storage and Reset, and turning it off while listening stops the dictation and keeps its text.
16. The switch, the model and the language survive a relaunch, and Reset puts them back to on, Apple and the language of macOS and keeps the downloads.
17. The microphone icon is in the message box of the new-session view and of the conversation while Dictation is on: a click starts and the next one stops, and Send is disabled while it listens.
18. While it listens nothing is written in words: the box's line follows the level and the icon fills, with Reduce Motion keeping the brightness and stopping the turning and the drift, and Reduce Transparency keeping the edge only.
19. Getting ready and transcribing show their spinner and their caption, and a failure to start shows its cause in red under the box.
20. Switching session, closing the window and sending the app to the background stop the listening and keep what was heard.
21. VoiceOver has a label for each state and announcements for the start, the stop with the number of words added and a failure, and does not announce partial text; the icon is reached by keyboard before Send.
22. The app declares the microphone's usage and the build fails without it.
23. `THIRD-PARTY-NOTICES.md`, the glossary, the macOS README and the ADR 0016 note agree with all of the above.

## Decisions

The boundary and what is logic live in `CarrierCore`, which has no dependencies and stays that way; the three recognizer adapters, which import `Speech`, `AVFoundation`, FluidAudio and WhisperKit, live in the `Carrier` target, as Sparkle does. One controller in `Carrier`, main actor and observable, owns the session and is what the box and the page read. [0023](../adr/0023-dictation-runs-on-recognizers-with-a-fixed-list-of-downloadable-speech-models.md) holds the rest of the structure; this is the shape of the boundary, trimmed to what a ticket must not change. Audio with no speech in it ends in `final("")`, never in a failure, and a partial replaces the one before it.

```swift
public enum PartialText: Sendable { case native, chunked, atTheEnd }

public struct SpeechModel: Identifiable, Sendable, Equatable {
    public let id: String                // "fluidaudio.parakeet-tdt-v3"
    public let recognizer: RecognizerID  // .apple, .fluidAudio, .whisper
    public let name: String
    public let bytes: Int64?             // nil for Apple's: the system manages them
    public let languages: Set<String>    // base codes ("es"); Apple's come from the system
    public let detectsLanguage: Bool
    public let partial: PartialText
    public let licence: String
    public let card: URL                 // https, on a host the catalog allows
}

public enum DictationEvent: Sendable, Equatable {
    case partial(String)
    case final(String)
    case failed(DictationFailure)
}
```

The level is a pure function of a buffer's root mean square, `0...1` linear. It was checked against the inputs it takes: `0`, a negative and NaN return `0` through the guard; `0.0025` (−52 dB) and anything quieter return `0`; `0.079` (−22 dB) returns `1`; a clipped buffer above `1` and positive infinity return `1`. The smoothing is the view's, stepped on every frame: it goes up to a new level in about 30 ms and lets go of it in about 200 ms (`VoiceFollower`).

```swift
func normalizedLevel(rms: Float) -> Float {
    guard rms > 0 else { return 0 }
    let decibels = 20 * log10(rms)
    return min(1, max(0, (decibels + 50) / 40))
}
```

The text of a dictation is a value with a tentative range, kept apart from the field: a partial replaces the range's content, a final replaces it and closes it at the caret, an empty final removes it, and nothing outside the range is touched, whatever the text is, empty included, and wherever the caret is, at either end included. The language the page offers is a pure function of the model, the languages of macOS and the saved choice, which is what story 12 pins. What the box draws (the icon, the caption, whether Send is enabled, whether the edge is on and the labels for VoiceOver) is a pure function of the session's state, so that the views stay thin.

The preferences are `dictation.enabled` (true when absent), `dictation.model` and `dictation.language` in user defaults, read and reset through `AppPreferences`, with a `.dictation` page in its reset. An unknown saved model falls back to Apple's. The log is the app's own, `app/logs/dictation.log`, beside the `app-upgrade.log` precedent.

Both libraries are asked for their download directory and are used offline once a model is on disk. FluidAudio's `loadModels` deletes and downloads again a cache it finds damaged, which is why its offline mode is on at every load and the person's explicit download is the only call that is not offline.

Testing seams, story by story. Swift Testing, in `macos/Tests/CarrierCoreTests` over `@testable CarrierCore`, as the other pages' logic is tested; the adapters that need a model are gated tests that skip themselves, as the engine's integration tests do.

- Stories 1, 2, 3, 5, 7, 15 (the stop): `DictationSession` with a scripted capture, a scripted recognizer and a fake clock, in `DictationSessionTests`. One test drives a whole dictation; the failures, the second dictation, the typed key, Enter and the switch turned off while listening are each a short script. Story 7 asserts the session holds no file and the capture's buffers are released at the end.
- Story 4: `AudioLevel` with a table of inputs, the ones listed in Decisions, and the smoothing's rise and fall; the edge's opacity function beside it.
- Story 5, the text rules: `TentativeText` with a table: empty box, caret at each end, a partial then a final, an empty final, text typed during.
- Story 6: the chunking layer with a scripted batch recognizer and the fake clock, in its own tests. They pin the contract that holds whatever the policy is: a word already final is never lost, the stop gives a final, a model too slow gives no partial. The tests of the policy itself are written from the result of the second open question.
- Stories 8, 12: `SpeechModelCatalog` with its invariants (ids are unique, a licence and a link on an allowed host are never missing, a model that detects the language says so) and `languageChoices` with a table: each model kind, the macOS languages with and without Apple's supported one, a saved language not on offer. The catalog check on the real models is a gated test per entry, which loads the model from a folder named by `CARRIER_IT_DICTATION` and transcribes a short clip of Spanish speech that sits in the test resources.
- Stories 9, 10: `ModelStore` with a fake downloader and a temporary folder: the states of a model, the progress, the cancel, the failure with each cause, the partial file removed at launch, no delete of the model in use, the folder layout under `app/models`. Whether a library fetches on load is asserted in the adapters' gated tests, which load a model with the network refused.
- Story 11: the microphone's permission through its port, mapped to allowed, denied and not asked, in the session's tests; the default model in `AppPreferencesTests`.
- Story 13: the three adapters, each one gated test: it listens to the Spanish clip through the real library and asserts text that is not empty, with the model loaded offline.
- Story 14: `SettingsRailTests`, whose list of pages gains `.dictation` after `.chat`, and an `ImageRenderer` of the page, as the rail's test does; the rows the switch dims are a pure function and have a test of their own.
- Story 16: `AppPreferencesTests` with a suite of defaults: survive a relaunch, an unknown model, Reset keeping the downloads.
- Stories 17, 19, 21: the presentation function of the session's state, with a table of states and what the box draws and says; the box itself is rendered with `ImageRenderer` in each state so that a layout does not blow up. No test of the hit area or the focus order: checked by hand with the keyboard and VoiceOver on the fixture build, as the other specs do.
- Story 18: no unit tests: the opacity is covered by story 4 and the rest is drawing; checked by hand on the fixture build, light and dark, with Reduce Motion and Reduce Transparency, against the numbers of the design page, and its cost measured on battery. The `NoHandSetFontSize` test already covers every view's sizes.
- Story 20: no test of the notifications' wiring, which is thin; the stop that keeps the text is story 3's test.
- Story 22: the check in `build-app.sh` itself, which fails the build, as it does for the icons.
- Story 23: no tests, a documentation change.

## Out of scope

Dictation outside Carrier: the shortcut, hold to talk, Escape and the other keys, typing into other apps and the overlay. Cleanup of the text with a language model and a personal dictionary: both are wanted, later, on this core. A "try it" row in Settings, where a person speaks and sees the text without leaving the page. Dictation into any text field of the app other than the message box. Choosing the input device: it is the system's. Transcribing files or meetings. Any model outside the fixed list, including a person's own, and a download that nobody asked for. Changing how the app is signed or installed: the ad hoc signing of [0017](../adr/0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md) stays. A Mac that is not Apple Silicon, which the app already excludes.

## Open questions

Whether Apple's SpeechAnalyzer asks for the speech recognition permission besides the microphone, which language assets it fetches and how long they take. It decides whether `NSSpeechRecognitionUsageDescription` joins the `Info.plist` and how long "Getting the model ready…" lasts on a first use. How it does in Spanish and in a mix of Spanish and English is worth knowing for the owner and decides nothing in this spec. A prototype settles it.

Whether the partial text the core makes by transcribing the audio so far is steady, without words changing under the person's eyes, how often it should transcribe, which words it holds as settled, and what it costs in processor time and battery. It decides the tests of story 6 and whether Parakeet TDT v3 keeps the label Live; if it is not steady, the label of the models that rely on it becomes When you stop. A prototype settles it, on Parakeet TDT v3 first.

Whether the microphone permission survives a Sparkle update with the ad hoc signing, or macOS asks again each time. In this cut it costs a new prompt; for the global dictation, which needs the Accessibility permission too, it decides how it can be built. A prototype settles it by installing a build, allowing the microphone and updating to the next.
