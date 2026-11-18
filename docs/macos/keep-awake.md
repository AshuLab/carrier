# Keep awake

Keeps the Mac from sleeping on its own, by hand or while agents work. It is in the menu bar's menu and on its own Settings page (`Carrier/KeepAwakeTab.swift`, `SettingsPage.keepAwake`, in the App group after Dictation).

## What the person sees

- **The menu** (the status item's, under the Pause and Stop controls): the first item says what a click does, with the state under it. "Keep awake for 1 hour" starts the default length; with a keep awake by hand running it reads "Stop keeping awake". Under it: "Off", "Awake · 1 h 12 min left", "Awake until you turn it off", "Awake while agents work", "Awake · 4 min after agents finished", "Paused: battery at 18 %" or "Off · wakes up when agents work".
- **Keep awake for**, a submenu of lengths (30 min, 1 hour, 2 hours, 5 hours, Until I turn it off) with the one that runs checked, and a way to the page.
- **Keep awake while agents work**, a checked item: the same switch as the page's.
- **The icon**: a small cup shows before the count and the bar while the Mac is held awake, and goes when it is not. A Mac that Carrier is not running on still shows the cup in full: the rest of the icon is faded, the cup is not.
- **The page**: Now (the state, a chip On, Off or Paused, and the button the menu's first item is), By hand (Length, Keep the screen on, Shortcut), With agents (the switch and Stay awake after they finish: Right away, 5, 15 or 30 min) and Battery and notices (On battery, and Tell me when it stops by itself). Reset puts the page back.
- **The shortcut** turns keep awake on or off from any app. There is none until it is recorded (so no installed app loses a combination); the recorder is Dictation's (`ShortcutRecorderRow`), with Clear.

## The rules

- It holds when something asks for it and the battery does not forbid it. What asks: a keep awake by hand (a length, or no end), or, with "While agents work" on, an epic running or a chat session working. After the work stops it holds for the grace, counted from the last time work was seen. A keep awake by hand wins over the agents: it shows its own time.
- Nothing is on when Carrier opens: a keep awake by hand is not kept across a relaunch, so nobody spends the battery without knowing. The switch "While agents work" is kept, and is off by default.
- **Battery**: on battery, Stop below 20 % (the default; 30, 10, never, or only while plugged in). Paused is not off: it goes on by itself when the Mac is plugged in or charged again. A Mac with no battery is never on battery.
- **The screen**: the Mac is held awake and the screen may sleep. "Keep the screen on" holds the display too.
- **What it does not stop**: closing the lid and Sleep in the Apple menu. An assertion cannot, and the page says so. The way that does (`pmset disablesleep`) needs an administrator password and leaves a setting of the whole system behind if the app dies; it is not used.
- **A notification** when it stops by itself: a keep awake by hand that ran out, or the battery's pause. Not when the person stops it, changes a setting, or the agents' own keep awake ends after the grace (that is the ordinary end and says nothing). The Notifications page's quiet hours do not apply: it only fires on an end the person did not make.

## How

One power assertion for the system (`PreventUserIdleSystemSleep`) and one for the display (`PreventUserIdleDisplaySleep`), through `IOPMAssertionCreateWithName` in `KeepAwakeController`. They are the system's own: they go when the app quits or dies, with no child process and no password. The decision, the time left and the words are pure functions in `CarrierCore/KeepAwake.swift` (`awakeDecision`, `awakeStatus`, `awakeRemaining`, `awakeToggleTitle`, `nextAwakeChange`), tested in `KeepAwakeTests`; the controller feeds them the epics running (from the engine's snapshot), the chat sessions working (from the host's list, zero when the host does not answer), the battery (`IOPSNotificationCreateRunLoopSource`) and the settings, and a timer wakes it at the end of a length or of the grace.
