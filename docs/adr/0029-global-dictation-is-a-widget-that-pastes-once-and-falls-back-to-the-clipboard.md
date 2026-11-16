# 0029 - Global dictation is a widget that pastes once at the end and falls back to the clipboard

- Status: proposed
- Date: 2026-11-16

## Context

[0023](0023-dictation-runs-on-recognizers-with-a-fixed-list-of-downloadable-speech-models.md) built dictation inside the message boxes and left the global one for its own epic, because it needs the Accessibility permission, a global key and writing into other apps, and those depend on how the app is signed ([0017](0017-carrier-is-installed-with-a-homebrew-tap-and-the-app-is-not-signed-with-a-developer-id.md)): with an ad hoc signature macOS may forget a permission when Sparkle replaces the app. The owner wants to stop using FluidVoice, so this is the epic.

In the message box the session writes partial text into a field the app owns and rewrites it as the model corrects itself. In another app there is no such range: whatever is typed there stays, and a batch model that rewrites words far back would leave garbage the person cannot fix.

## Decision

One global shortcut, configurable, starts and ends a dictation, as a toggle or as a hold (a setting). What it does depends on where the person is. With Carrier in front on a session and its composer, the app focuses the composer and dictates into it as it does today, with no widget. Anywhere else a floating widget appears over the screen, without taking the focus from the app the person is in.

The widget shows the text as it is heard, read only. When the person ends the dictation, and the cleanup of [0030](0030-dictation-cleanup-runs-on-local-model-servers-through-their-api.md) is on, it shows that it is working and then gives the result; the text is pasted once, into the field that has the cursor. If no text field has the cursor, or the app lacks the permission to paste, the text stays in the widget with a Copy button and is also put on the clipboard, and the widget says why. Escape cancels without pasting.

The shortcut itself is registered as a system hot key, which is expected to need no permission; the Accessibility permission is asked for only to see whether a text field has the focus and to paste into it. A dictation never loses its text because a permission is missing.

## Alternatives considered

Typing into the other app word by word, as partial text arrives. It looks alive, but it cannot take back a word, and it needs the permission on every word, not once.

A separate shortcut for Carrier and another for everywhere. Two keys to learn for one action; the app already knows where the person is.

A widget also inside Carrier, handing the text to the composer at the end. It makes the widget the only path and costs the feel of dictating where the text will be; the inline dictation already works and has the partial text.

Refusing to start without the permission. Honest, and a worse experience than a dictation that still ends in the clipboard.

## Consequences

The widget is a new window kind in the app, not activating, always on top, with its own position and states (listening, working, ready, copied, failed, cancelled). The dictation core stays the one that [0023](0023-dictation-runs-on-recognizers-with-a-fixed-list-of-downloadable-speech-models.md) built, with a target that is either a box or the widget.

Pasting goes through the clipboard and a synthesized paste key, so the person's clipboard is overwritten unless the app keeps and restores it; that is to be settled in a spike with the focus detection.

Whether the permission survives a Sparkle update with an ad hoc signature, and whether a hold needs key-up events that the system hot key gives, are measured before the build counts on them.
