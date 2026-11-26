# Dictation

**Dictation** - Speaking to write: the app listens through the microphone and puts the recognized text where the person is typing. It starts from the button in a message box, which fills that box, or from the global shortcut ([0029](../adr/0029-global-dictation-is-a-widget-that-pastes-once-and-falls-back-to-the-clipboard.md)).
_Avoid_: voice input, transcription (a recording turned into text afterwards), speech-to-text (that is what a recognizer does).

**Recognizer** - The piece of software that turns audio into text, each with its own list of speech models: Apple's SpeechAnalyzer, FluidAudio (Parakeet, Nemotron) and Whisper. A person picks a recognizer and then one of its models. It runs inside the app, not in the engine.
_Avoid_: engine (that is Carrier's orchestrator, and the app has an Engine page), backend, provider (that is who serves an agent's model), ASR or STT engine.

**Speech model** - What a recognizer runs, taken from one fixed list in the app: its name, recognizer, size, languages, how it gives partial text and its licence. It is downloaded by the person from the app, never bundled with it and never fetched from a free URL; Apple's are managed by the system.
_Avoid_: model alone (that is the language model an account's agent uses), voice, checkpoint.

**Partial text** - What a dictation shows while the person is still speaking, before it is final. A recognizer gives it natively, or the core makes it by transcribing the audio so far at short intervals when the model is fast enough, or there is none and the text arrives when the person stops.
_Avoid_: live transcription, preview, interim result.

**Global dictation** - A dictation started by the global shortcut from any app. With Carrier in front on a session it fills the composer as any dictation does; anywhere else it runs in the dictation widget and the text is pasted once, at the end, into the field that has the cursor.
_Avoid_: system-wide dictation, voice typing.

**Dictation widget** - The small floating window of a global dictation: it shows the text as it is heard, read only, then that it is cleaning, and at the end the text with a Copy button when nothing could be pasted. It never takes the focus from the app the person is in.
_Avoid_: overlay, HUD, indicator (that is the animated mark in a message box).

**Cleanup** - The step after a dictation that sends its text to a local language model with the person's one prompt (remove filler words, translate, make it technical) and uses what comes back as the result. If it fails the raw text is used.
_Avoid_: post-processing, rewrite, enhancement.

**Dictation history** - The list of what the person dictated: each entry has its text (as recognized and cleaned), the speech model, the time the transcription took and how it ended, and optionally its audio. It is separate from the dictation statistics, which are counters that survive deleting entries.
_Avoid_: transcript (that is a chat session's), log (that is `dictation.log`, causes of failure only).
