# Spike: global shortcut, focus detection and paste

Answers the input questions of [the global dictation spec](../specs/global-dictation.md) (issue #985, epic #983) and the Consequences of [ADR 0029](../adr/0029-global-dictation-is-a-widget-that-pastes-once-and-falls-back-to-the-clipboard.md): how the app registers a global shortcut with the key release a hold needs, how it reads what has the focus in another app and whether that is a secure field, and how it pastes without losing the person's clipboard. It writes no production code. The throwaway programs lived in a scratch folder outside the repository and are not part of the change.

## What was and was not observed

This spike ran on the owner's Mac from a process that is **not Accessibility-trusted** (`AXIsProcessTrusted()` is false, and so are `CGPreflightPostEventAccess()` and `CGPreflightListenEventAccess()`), and nobody could grant it. So nothing here was tried against a real key press or against another app's focus. Every claim carries one of two marks:

- **Observed**: a program or a command run on this Mac gave the result, and the result is quoted.
- **Documented, unverified**: it comes from Apple's headers or documented behaviour, or from what is generally known of these APIs. It has not been seen to work on this Mac, and the build must not count on it until the checklist at the end is run on the epic's integration PR.

Machine: Apple silicon, macOS 27.0 (26A428), Swift 6.4.2. One machine; the owner's own apps are what the collision section reads.

## The answer

**Hot key.** Carbon `RegisterEventHotKey` registers ⌥ Space and every other combination tried with no permission at all (observed). It has `kEventHotKeyPressed` and `kEventHotKeyReleased`, both of which a handler receives and tells apart (observed with events built in-process, which proves the handler and the parameters, not the keyboard). Delivery of a real press and release is **unverified**: no key could be pressed from here.

**⌥ Space collides.** It is the shortcut of three apps installed on this Mac: FluidVoice (the one this epic replaces), ChatGPT (its launcher) and Handy (its default). macOS itself does not use it (observed). Registration does not fail when another app has the same combination, so the collision is silent. **Default: ⌥⇧ Space**, which nothing found here uses; the shortcut stays configurable. See the section for the reasoning.

**Focus.** The plan is the system-wide element, `kAXFocusedUIElementAttribute`, role in `AXTextField`, `AXTextArea`, `AXComboBox`, subrole `AXSecureTextField` for a password, and `IsSecureEventInputEnabled()` as a second, permission-free sign of a secure field. Without the permission the call fails (observed: error -25204, `kAXErrorCannotComplete`), which is the "no permission" decision of `pasteDecision`. How it behaves in a web input, a terminal and a password field is **unverified**, and the expectation is that web inputs need a switch turned on and terminals may show no field at all.

**Paste.** Saving and restoring every type of every item of the clipboard works, byte for byte, in all seven cases tried (observed). The synthesized ⌘V and the delay before restoring are **unverified**; no number is proposed as a finding.

## Hot key

Evidence: a program that installs a handler for `kEventHotKeyPressed` and `kEventHotKeyReleased` on `GetApplicationEventTarget()` and registers each combination, run as a plain executable (an accessory `NSApplication`, no bundle, no entitlement, no prompt).

| combination | status |
|---|---|
| ⌥ Space | 0 (`noErr`) |
| ⌥⌘ Space | 0 |
| ⌃⌥ Space | 0 |
| ⌃⌥ D | 0 |
| ⌥⌘ D | 0 |
| ⌘ Space (Spotlight's) | 0 |
| ⌃ Space (input source) | 0 |
| Space alone | 0 |
| F5 | 0 |

`AXIsProcessTrusted()` was false before and after the registrations. So **a system hot key needs no permission** (observed), as ADR 0029 expected.

What else came out:

- **A status 0 does not mean the combination is free.** ⌘ Space and ⌃ Space are the system's own shortcuts and registered without an error, and ⌥ Space registered while FluidVoice, which owns it for the owner, was running. The settings recorder cannot use the status to warn about a collision.
- **Two registrations of the same combination: the second fails inside one process** (`eventHotKeyExistsErr`, -9878, observed) **and succeeds across processes** (two programs registering ⌥ Space at the same time both got 0, observed). Which of two apps gets the press is not known; it was not observed.
- **Pressed and released.** A handler for both kinds receives an event for each and reads the `EventHotKeyID` from `kEventParamDirectObject`: sending a built pressed and a built released event to the application target gave `["pressed#7", "released#7"]` (observed). That checks the plumbing of the handler, not that the system delivers the release of a held key.
- **A real press was not possible here.** Posting ⌥ Space with `CGEventPost` at the HID and the session tap, with no post-event access, reached no handler (`pressed: 0 released: 0`). Whether the system dropped them for lack of permission or for another reason was not told apart, so this proves nothing about delivery.
- **No modifier-only or fn shortcut with this API.** A hot key takes a key and modifiers. A shortcut made of a modifier alone (⌥ held, or fn) needs a listening event tap, and creating one failed here (`CGEvent.tapCreate` with `.listenOnly` returned nil, observed), which is the Input Monitoring permission. The spec's shortcut is a key plus modifiers, so it stays out of that.
- **Documented, unverified:** a hot key sends pressed once and no repeats while the key is held; the release arrives when the key (not the modifier) comes up, so a hold that ends by letting go of ⌥ first may end late or early; and while Secure Event Input is on (a password field has the focus) hot keys with a modifier are still delivered. The three are in the checklist because a hold depends on all of them.

## ⌥ Space on this Mac

- **macOS (observed, `defaults read com.apple.symbolichotkeys`).** The entries are Switch to Desktop 1 and 2 (⌃1, ⌃2), Move left and right a space (⌃←, ⌃→, with and without ⇧), a modifier-type entry (id 164, with the fn flag), and the two input-source shortcuts: id 60 is ⌃ Space (keycode 32/49, control) and id 61 is ⌃⌥ Space (control and option). So **⌃ Space and ⌃⌥ Space are taken** and out for a default. ⌥ Space alone and ⌥⇧ Space are not there. Spotlight (⌘ Space) and Finder search (⌥⌘ Space) are not in the file, so they are at the system defaults, which this spike took from general knowledge and did not read from the system: **⌥⌘ Space is Finder's search and a poor default**.
- **Installed apps with ⌥ Space (observed, their own settings):**
  - FluidVoice: `PrimaryDictationShortcuts` is keycode 49 (Space) with modifier flags 524288, which is Option. This is the owner's current dictation shortcut; the epic is solved when the app is uninstalled.
  - ChatGPT: `KeyboardShortcuts_toggleLauncher` is `carbonModifiers 2048` (Option) with `carbonKeyCode 49` (Space); its attached launcher is another combination.
  - Handy: default binding `option+space`, current `option_left+space`.
  - Alfred and Raycast are not installed. The Claude desktop app's settings files hold no shortcut. Nothing else on this Mac was found to use it; other apps' internal shortcuts were not searched.
- **In a text field, documented and unverified:** ⌥ Space types a non-breaking space in most Mac text fields. A hot key consumes the key before the field sees it, so it should not, but a person who types it in text loses that.

**Default to use: ⌥⇧ Space.** Three apps hold ⌥ Space here, and since registration across processes does not fail, a collision would show as two apps answering one press. The owner removes FluidVoice, but ChatGPT's launcher and Handy remain. ⌥⇧ Space keeps one hand position near the old one, is not a system shortcut (observed list) and is in no app's settings found here. The owner can still choose ⌥ Space after turning the others off. It is a default, not a measurement: the checklist asks to press it.

## Reading the focus in another app

The plan, from Apple's headers on this machine (`HIServices`, all constants present in the SDK):

1. `AXUIElementCreateSystemWide()`, then `AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute)` for the element with the keyboard focus. (`kAXFocusedApplicationAttribute` gives the app first, if the system-wide call fails on an app.)
2. On that element read `kAXRoleAttribute` and `kAXSubroleAttribute` (never `kAXValueAttribute`, which for a password holds the secret or its dots, and the app does not need it).
3. Decide:
   - **Editable**: role `AXTextField`, `AXTextArea` or `AXComboBox` (`AXSearchField` is a subrole of a text field and is also editable), and `AXUIElementIsAttributeSettable(element, kAXValueAttribute)` true, or `kAXSelectedTextRangeAttribute` present.
   - **Secure**: subrole `AXSecureTextField` (`kAXSecureTextFieldSubrole`).
   - **None**: no element, no role of those, or an error.
4. The error without the permission, observed: `AXUIElementCopyAttributeValue` on the system-wide element for `kAXFocusedUIElementAttribute` and for `kAXFocusedApplicationAttribute` both returned -25204 (`kAXErrorCannotComplete`), with `AXIsProcessTrusted()` false. It is not `kAXErrorAPIDisabled` (-25211), so the app must not wait for that code: **any error from the first call is "no permission or no field"**, and `AXIsProcessTrusted()` tells the two apart. `NSWorkspace.shared.frontmostApplication` works with no permission (observed, it named the browser that was in front), which is enough for the routing rule of the spec.

Where it can fail, all **documented or generally known, unverified**:

- **Native fields** (Cocoa text fields and views, Notes, TextEdit, Messages): the case the plan is written for. Expected to work.
- **Web inputs.** Safari and Firefox expose the page's fields. Chromium browsers and Electron apps (Chrome, Slack, Discord and VS Code are installed here) build their accessibility tree only after an assistive technology is detected; the usual switch is setting `AXEnhancedUserInterface` or `AXManualAccessibility` to true on the application element. Neither constant is in the SDK headers (searched), so they are strings the app would add. Without it, the focused element can be missing or be the page, which reads as "none" and the dictation lands on the clipboard.
- **Terminals.** Terminal.app shows its text as one `AXTextArea` whose value is the scrollback, so the role says "text" while a paste goes to the shell. Warp, iTerm2 and Ghostty draw their own surface and may show no element, or one without the roles above. Plausible result: terminals read as "none" or as an editable area whose `AXValue` is not settable. This decides whether the person can dictate into a terminal, which is a product question the owner answers on seeing the result; a rule of "paste anyway when the app is trusted and the front app is a known terminal" is available if "none" there is unacceptable.
- **Password fields.** Native secure fields carry `AXSecureTextField`. Web password inputs in a browser may show as a plain text field, or none. `IsSecureEventInputEnabled()` is a second signal that needs no permission: it is true while any app has Secure Event Input on, which a password field and Terminal's Secure Keyboard Entry turn on. Observed in-process only: `EnableSecureEventInput()` made it true and `DisableSecureEventInput()` made it false, and it was false in the system at the time (`ioreg` showed no secure input owner). Cross-app it is documented and unverified. The recommended rule is **secure when the subrole says so or when `IsSecureEventInputEnabled()` is true**: a stuck flag from another app costs a dictation that goes to the clipboard, never a password typed in the clear.
- **Alternative to the clipboard.** Setting `kAXSelectedTextAttribute` on the element inserts at the cursor with no clipboard, and works in native views and not in many web and Electron fields. Not tried; the ADR chose the paste, which works in more places.

## Paste and the clipboard

**Putting the clipboard back, observed.** A program wrote each case to `NSPasteboard.general`, took the snapshot a paste would take, wrote the dictated text with the transient marker, and restored from the snapshot. In all seven cases the items, the types of every item and the bytes of every type came back identical:

| case | items and types | restored identical |
|---|---|---|
| plain text | 1 item, 1 type | yes |
| rich text: RTF, HTML and plain text in one item | 1 item, 4 types (the system adds `public.utf16-external-plain-text`) | yes, same order |
| image: TIFF and PNG | 1 item, 2 types | yes |
| two files, as Finder copies them | 2 items, 2 types each (`public.file-url` and the name) | yes |
| concealed: `org.nspasteboard.ConcealedType` and `TransientType` with plain text | 1 item, 3 types | yes, markers included |
| custom type of 1 MB with plain text | 1 item, 2 types | yes |
| empty clipboard | 0 items | yes |

How it is done:

- Snapshot every `pasteboardItems` entry, and for each `item.types` entry its `data(forType:)`. Restore with `clearContents()` and `writeObjects` of new `NSPasteboardItem`s, one per saved item, calling `setData` for each type. Saving only the string, or only the first item, would lose the images, the files and the markers above.
- **Items cannot be reused**: writing an item that was read from the clipboard throws `NSInvalidArgumentException` ("already associated with another pasteboard", hit by the program). A restore builds new items.
- **Lazy data.** An item whose data is promised by a data provider is asked for it on the snapshot (the provider ran once per type, observed), so a snapshot can cost what the owner app takes to render a big promised flavour. Nothing came back missing in any case tried.
- **Cost, observed:** a snapshot of 1 MB took 2.6 ms and of 20 and 100 MB about 0.1 ms (the data is read lazily and not copied at that point, so this is not the cost of using it); writing the dictated text took 0.2 to 2 ms; restoring took 0.5, 3 and 13.6 ms for 1, 20 and 100 MB. None of it is a reason for a delay.
- **`changeCount`, observed:** every `clearContents` plus write moved it by one. The restore writes after the dictated text, so a count that differs from the one the app got when it wrote means the person copied something during the wait: the app then **does not restore**, and the person's newer copy stands. This is derived from the counts above, not a separate run.
- **Markers.** `org.nspasteboard.TransientType` is not in Apple's headers (searched); it is the convention of nspasteboard.org that clipboard managers read to skip an item. Write it on the dictated text so a clipboard manager does not keep every dictation. The restore copies the person's own types, markers included, unchanged. `NSPasteboardContentsCurrentHostOnly` (a header option of `prepareForNewContentsWithOptions`) keeps the temporary text from going to other devices through Universal Clipboard; it was not tried.
- **Pasteboard privacy prompt.** The header says that, from macOS 15.4, reading the general pasteboard programmatically asks the person for permission by default, except for access that is both user-originated and a paste (`NSPasteboard.accessBehavior`, `.default` ask). In this spike the program read `accessBehavior` and got 2 (always allow), so it did not prompt. Whether the ad hoc signed `Carrier.app` does is **unverified**, and a prompt at the first dictation would cost the snapshot. The writing needs no prompt.

**Sending ⌘V, unverified.** The plan is a `CGEvent` key down and key up of `kVK_ANSI_V` with `.maskCommand`, posted to `.cghidEventTap`, which needs the post-event access of Accessibility (here `CGPreflightPostEventAccess()` was false, and the events posted had no effect that could be seen). Two things to settle:

- **Held modifiers.** In a hold, ⌥ and ⇧ may still be physically down when the paste is sent, making it ⌥⇧⌘V (paste and match style in many apps). Either wait for the modifiers to come up or send the event from a source that ignores the physical state.
- **The delay.** The target app reads the clipboard when it handles ⌘V, after the app has posted it; restoring too soon pastes the person's old clipboard instead of the text. No number was measured, and none is proposed as a finding. A first value to try, and only a guess to be calibrated, is 200 ms, tried against the sweep of the checklist; if it differs a lot by app the restore can wait for `changeCount` plus a fixed minimum instead of a single constant.

**Where paste fails, documented and unverified:** apps that ignore synthesized key events (some games and remote-desktop clients); terminals that treat ⌘V as bracketed paste and may run text with newlines, so the text of a dictation should not end with a line break; and a password field, which the rule above excludes before the paste is sent.

## What changes in the spec

- The default shortcut in the settings and the recorder: ⌥⇧ Space instead of ⌥ Space, and the recorder cannot warn of a collision from the registration status (observed).
- `pasteDecision` stays as written, with `secure` meaning the subrole or `IsSecureEventInputEnabled()`. The "no permission" case is any failure of the first AX call with `AXIsProcessTrusted()` false.
- The open question "does a hold get the key release" stays open until step 1 of the checklist; if it fails, the hold is dropped and the toggle is the only activation.

## Verify on the integration PR

Run these with a build that has the Accessibility permission, in this order. Each says what to write back on the PR.

1. **Press and release.** Register the shortcut and hold it for two seconds in a text editor: one pressed, one released, no repeats in between? Release ⌥ before the space bar, and the space bar before ⌥: when does the release come? Press it in a password field of a browser with Secure Event Input on: does it still arrive?
2. **⌥⇧ Space and the collision.** Press ⌥⇧ Space with ChatGPT and Handy running: only Carrier answers? Then ⌥ Space with ChatGPT running: who answers? Does ⌥⇧ Space type or do anything in a text field, Safari and Chrome?
3. **Native field.** With the permission, in TextEdit and in a Notes note, read the focus: role `AXTextArea`, `AXValue` settable? Paste a dictation.
4. **Web input.** In Safari, Chrome and Firefox, in a text input, a textarea and a `contenteditable`: is the focused element found, with what role, before and after setting `AXEnhancedUserInterface` or `AXManualAccessibility` on the app? Paste.
5. **Terminals.** In Terminal.app, iTerm2, Warp and Ghostty at a shell prompt: what element and role does the system-wide focus return? Does the paste land? Does a dictation with a newline run a command?
6. **Password fields.** In a native password field (a System Settings unlock, Keychain Access) and a web password input in Safari and Chrome: subrole `AXSecureTextField`? `IsSecureEventInputEnabled()` true? Is the paste refused and the text left on the clipboard?
7. **The paste.** From a hold, with ⌥ and ⇧ still down at the moment of the paste: does the app receive plain ⌘V? Sweep the restore delay at 0, 50, 100, 200, 400 and 800 ms against TextEdit, Chrome, Slack, VS Code and a terminal: the smallest delay at which the text always lands and the old clipboard comes back, and what each app does at 0.
8. **Clipboard restore for real content.** With a Finder file copy, a screenshot on the clipboard, rich text from Pages and a 1Password copy on the clipboard, dictate and paste, then paste again: is each one back, markers included? Does a clipboard manager (if the owner runs one) record the dictation text and the restore?
9. **Pasteboard prompt.** First dictation of the ad hoc signed build: does macOS ask to allow Carrier to read the pasteboard? Is the dictation's snapshot slow or lost if the answer is no?
10. **Copy during the wait.** Copy something during the delay between the paste and the restore: the app does not restore and the new copy stays?
