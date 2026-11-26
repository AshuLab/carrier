# 0031 - Dictation keeps a history, and its statistics live apart from it

- Status: proposed
- Date: 2026-11-16

## Context

Until now dictation kept nothing of what the person said: `DictationLog` holds the cause of a failure, "never the audio or the text", and the audio lives in memory until the capture stops. The owner wants a list of his dictations with search, copy and delete, with how long each took to transcribe and the model that did it, and statistics on how much he dictates: words and dictations by day and hour, a weekly summary, the time saved against typing at 40 words a minute, records. He also wants to choose whether the text and the audio are kept at all.

## Decision

The app keeps a history of dictations in its own folder, `<Carrier folder>/app/`, with one entry per dictation: when it started, the text as recognized and the text after cleanup if there was one, the speech model, how long the transcription took, the length of the audio, the words, where it went (a Carrier box, an app, the widget only) and how it ended (pasted, copied, cancelled, failed). A cancelled dictation is recorded as cancelled. Keeping the text is a setting, on by default.

Keeping the audio is a separate setting, off by default. When it is on, each entry points to its audio file, and a limit of days, 30 by default, deletes the old files. The person can delete every audio at once and keep the transcripts; deleting an entry deletes its audio.

The statistics are counters of their own, per day and hour, with words, dictations, seconds dictated and the model, and no text. They are written when a dictation ends whatever the history settings say, so turning the history off or deleting an entry does not change them. A Reset statistics button deletes them. The time saved is the words divided by 40 words a minute, minus the time spent dictating; the 40 is a setting.

## Alternatives considered

Statistics as a query over the history. One store and less to write, and the numbers disappear when the person cleans up or turns the text off, which are the moments he is most likely to want them kept.

History off by default, as the log is. It follows the earlier line of keeping nothing, and the owner asked for the list as a feature, not as an opt-in for the careful.

Keeping the audio always, or with no limit. It makes every entry replayable and grows the disk without anyone choosing it.

## Consequences

Dictation now stores what the person says, in plain text on the Mac, until they delete it. The history page says so and turns it off in one place; `dictation.log` still never holds text.

There are two stores to keep in step, the entries and the counters, and the counters cannot be rebuilt from entries that were deleted.

The audio files and the 30-day sweep are a second thing for the app to clean at launch, next to the speech models folder.
