# Design

**Front-end** - A program that draws Carrier for a person and talks to the engine and the chat host only through their sockets: the terminal panel, the macOS app, and the web front-end to come.
_Avoid_: UI, client (on its own), app (that is the macOS one).

**App area** - One part of a front-end that a person meets as a whole (Sessions, Chat, Epics, Terminal, Dictation, Projects, Usage, Settings and the like), described by one doc under `docs/macos/` and kept in one folder per layer ([0052](../adr/design/0052-the-macos-app-is-split-into-three-targets-by-layer-and-each-target-by-area.md)).
_Avoid_: module, feature (a feature is what a spec ships), tab, page (a page is one row of Settings).

**Piece** - A reusable building block of a front-end's look (a kind of button, a row, a select, a meter, an empty state), named and explained in `docs/ui.md`; it takes values and actions, gets its theme and text size from the environment, and knows nothing of sessions, epics, sockets or the app's shared state ([0052](../adr/design/0052-the-macos-app-is-split-into-three-targets-by-layer-and-each-target-by-area.md)).
_Avoid_: component, control, widget (the dictation widget is a thing of its own).

**Platform adapter** - The code that does, for one front-end, what only its platform can (a recognizer, keep awake, a notification, an update, a global shortcut, a terminal surface), behind a protocol of the core.
_Avoid_: service, helper, bridge.

**Design token** - A named value of the look (a colour of a theme, a text size, a spacing, a radius, a duration) that every front-end takes from `design/tokens.json` ([0054](../adr/design/0054-the-look-the-words-and-the-apps-preferences-have-one-neutral-source-generated-for-each-front-end.md)).
_Avoid_: magic number, theme value (a theme is one of the palettes).

**Copy key** - The name of one user-facing text in `design/copy/`, with its arguments and plural forms; each language gives its own words for it.
_Avoid_: string, message (that is a chat message), label (that is GitHub's).

**Text code** - The stable name of a text Node sends a person (`session.switching`, `doctor.ghMissing`), sent with its parameters and English words; a front-end shows its own words for it ([0055](../adr/design/0055-a-refusal-carries-a-code-and-its-parameters-and-its-english-words-are-the-fallback.md)). A refusal code is the text code of a refusal.
_Avoid_: error message, error code (an engine error is a kind of stop), message (that is a chat message).

**Theme** - A named palette of the look: the colour of the windows, the colour of the sidebar and an accent, each in a light and a dark version of which the colour scheme picks the one shown, plus a 16-colour palette for the terminal; the catalog is open and grows by themes, not by a number.
_Avoid_: skin, palette (that is the terminal's 16 colours), colour scheme (that is light, dark or system).

**Theme gallery** - The piece that shows the themes as cells, each with its light and its dark preview, in three rows that scroll sideways; the app and the terminal both choose a theme with it.
_Avoid_: theme picker, theme list.
