# Carrier keeps the Mac awake, by hand or while agents work

Status: implemented (unreleased)

## Problem

Carrier runs agents for minutes or hours, and a Mac that goes to sleep in the middle cuts the job.
People work around it with a separate keep-awake app, or with `caffeinate` in a terminal, and forget it is on or that it is not.

We know it is solved when a person can keep the Mac awake from the menu bar in two clicks, can have Carrier do it by itself while agents work, and always sees whether it is on and when it ends.

## Solution

The menu bar's menu has a Keep awake item that does what its title says ("Keep awake for 1 hour", or "Stop keeping awake" while one runs), with the state under it, a submenu of lengths and a switch "While agents work".
A small cup shows on the icon while the Mac is held.
Settings has a Keep awake page with the length, the screen, a shortcut for any app, how long to stay on after the agents finish, what the battery does, and a notice when it stops by itself.
What each shows is in [keep-awake](../macos/keep-awake.md).

The Mac is held with the system's power assertions (`PreventUserIdleSystemSleep`, and `PreventUserIdleDisplaySleep` when the person asks for the screen too), taken in the app.
They are released by the system when the app quits or dies, and need no password.

## Scope

1. As a person, I keep the Mac awake for 30 minutes, 1, 2 or 5 hours, or until I turn it off, from the menu bar, and the menu says how long is left.
2. As a person, I see on the icon that the Mac is being held, without opening the menu.
3. As a person, with "While agents work" on, the Mac is held while an epic runs or a chat session works, and for a few minutes after (0, 5, 15 or 30), and not otherwise.
4. As a person, on battery the keep awake pauses below 20 % (or 30, 10, or never, or whenever the Mac is not plugged in), says so, and goes on by itself when the Mac is plugged in again.
5. As a person, I am told when a keep awake ends by itself, so a sleeping Mac is not a surprise, even with Carrier in front; I am not told when I ended it, or when the agents' own ended after the grace.
6. As a person, if I ask for a keep awake and the battery's rule stops it from starting, I am told so at once and it starts by itself when the rule allows.
7. As a person, I turn it on or off from any app with a shortcut I record; none is set until I do.
8. As a person, the screen may sleep unless I ask to keep it on.
9. As a person, a keep awake by hand does not survive quitting Carrier.

## Decisions

- **Assertions, not `pmset`.** Closing the lid would also need `sudo pmset disablesleep`, which asks for an administrator password each time and changes a setting of the whole system that stays if the app dies.
  Not used; the page says that the lid and Sleep in the Apple menu still sleep the Mac.
- **Nothing is on at launch and the switch for agents is off by default.** Holding the Mac awake costs battery, so it is never a surprise: the person turns it on, and a keep awake by hand is forgotten with the app.
- **A keep awake by hand wins over the agents** and shows its own time; the agents' one takes over when it ends.
- **No default shortcut.**
  The system does not say when another app already holds a key, so a default could look like it works and not.
  None is chosen for the person; when the system does refuse the keys (Carrier's own Dictation holds them, say) the page says so, and Dictation's keys and these cannot be the same.
- **The screen is off the assertion by default.** An agent needs the Mac awake, not the display; holding the display costs more power.
- **Not built:** triggers by app (hold while a given app runs), schedules, and holding with the lid closed.
