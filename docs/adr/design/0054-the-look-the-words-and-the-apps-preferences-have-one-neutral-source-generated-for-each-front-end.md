# 0054 - The look, the words and the app's preferences have one neutral source, generated for each front-end

- Status: proposed
- Date: 2026-11-24

## Context

The app's look lives in Swift: `CarrierCore/Theme.swift` holds the nine themes as hex values in a `switch`, `TypeScale.swift` the text scale, and the views add their own numbers (156 `cornerRadius:` with a literal, 65 `.padding(n)`, 37 `Color(red:)`).
Its words live in Swift too: 254 literal `Text("...")` in the views and many sentences built in `CarrierCore`, with no localization at all (`Package.swift` has no `defaultLocalization`).
Its preferences are read and written in 56 files (208 `@AppStorage`, 49 `UserDefaults`), and their keys, values and defaults are spread across them, though `AppPreferences.swift` holds many.
A web front-end has to draw the same colours and sizes, say the same words, and offer the same preferences, and the app has to be translated, to English and Spanish first.
Apple's catalog format, `.xcstrings`, is JSON and handles plurals, but it is Apple's; the web has its own conventions (ICU MessageFormat, CSS variables).

## Decision

One folder, `design/`, is the source of three things, and a script in the repo generates the code of each front-end from it; the generated files are committed, and CI fails when they differ from what the script makes.

- `design/tokens.json`: the design tokens, in two layers. The base layer is the colours of each theme in light and dark, the accent presets, the text sizes and weights, the spacing, the radii, the borders, the opacities and the durations. The semantic layer names what a colour is for and points at the base (the status colours, the kinds of tool call, attention, the accent's glass and selected row), since about a dozen colours of the app live outside the themes today (`ChatToolGroupView`, `SessionRowView`, `ChatApprovalView`, `ToolbarPillButton`). It generates Swift values in `CarrierCore/Theme/` and, for the web, TypeScript values and CSS variables. The rules for using them stay in [`docs/ui.md`](../../ui.md).
- `design/copy/en.json` and `design/copy/es.json`: every user-facing text, by copy key, in a restricted ICU MessageFormat. It generates the app's `Localizable.xcstrings` and a Swift accessor per key (`Copy.epicsWaiting(count:)`), and, for the web, a typed TypeScript function per key that formats numbers with `Intl.NumberFormat` and picks plurals with `Intl.PluralRules`. English is the source language; a key missing in Spanish, or one whose arguments differ from English, fails CI.
  - The subset: `{name}` (a string), `{name, number}` (an integer with no style), `{name, plural, ...}` with `=0` and the CLDR categories (`one`, `two`, `few`, `many`, `other`, which is required) and `#`, and `{name, select, ...}`. A plural or select may hold one more plural or select and no deeper; a message has at most one select argument; each select branch uses the same arguments in every language. No `selectordinal`, `date`, `time`, number styles, other `=N`, `offset` or apostrophe quoting.
  - A key is a whole sentence: code that builds a sentence from pieces with `+=` becomes one key, and the caller computes the select value or clamps a count to 0.
  - An identifier (an issue or pull request number, a version) is a string argument, never `number`, so it is never grouped ("#1.234").
  - Numbers and plurals follow the full locale, language and region; a value formatted before it is passed (a duration, a size, a list, a weekday) comes from a formatter of the same locale, and a translation rephrases around it rather than agreeing with it.
  - In the catalog every plural is a substitution (`%#@name@`), `=0` is Apple's `zero`, each select branch is its own key (`key.branch %lld %@`) behind a generated Swift enum, and the values use positional specifiers so a translation can reorder arguments.
- `design/preferences.json`: the schema of the app's preferences, each key with its type (`bool`, `int`, `double`, `string`, an enum's values, each of them optional), its default and the Settings page whose Reset clears it, so the hand-written list of keys per page is generated. Keys that hold state rather than a choice (the per-session `chat.options.<id>`, the last Settings page, Sparkle's own) are not preferences and stay where they are. It generates the Swift declarations `AppPreferences` reads and the TypeScript ones; every read and write of a preference goes through `AppPreferences`, and no view uses `@AppStorage` or `UserDefaults` directly. Each front-end keeps the values its own way (user defaults, the browser's storage).

Every user-facing text is a copy key, not only `Text(...)`: labels, buttons, toggles, fields' prompts, help, accessibility labels, alerts, menu items, notifications, Settings' search index and the titles that enums give; about two thousand in all. Code that finds something by its English title (`MainMenu` finding the Services menu, `SettingsIndex` making its anchors, the last Settings page saved by its title) finds it by a stable identifier instead. Dates, times and relative times are formatted for the person's locale, not `en_US_POSIX`.
`Copy` reads the catalog from `carrierResources`, CarrierCore's bundle in `Contents/Resources`, because SwiftPM's `Bundle.module` looks next to the `.app` and traps there.
The app declares Spanish in `CFBundleLocalizations` only once every key has its Spanish words, because declaring it turns macOS's own texts (alerts, the system's menu items) Spanish at once; until then the app is English with the catalog in place.
The language follows the system's choice for the app (macOS lets a person pick a language per app once the app declares its localizations) and the browser's; there is no language setting of Carrier's own.
A sentence that the core builds from data stays a function in `CarrierCore`, now returning a copy key and its arguments; shared fixtures (a key, its arguments and the expected text in each language) run in the Swift tests and, later, the web's, so both front-ends are checked to say the same.

## Alternatives considered

`.xcstrings` as the source, read by a script for the web.
It is what the app understands natively and has an editor in Xcode, but it makes the web a second-class reader of Apple's format, and a translation tool would have to work in it.

Style Dictionary for the tokens.
It does the same generation, but it is a dependency for a file a short script can turn into two outputs.

Reading the source at run time instead of generating code.
It saves the generator, but a missing token or key would show up as a blank on screen instead of a compile error.

## Consequences

Editing a text or a colour means editing `design/` and running the script, not touching a view.
The Xcode catalog editor is no longer where translations are made, since its file is generated.
The translations are the one exception to "all repo content is in English" in `AGENTS.md`, which says so.
Tests that compare the app's English words keep working by running with the English locale.
Two prototypes back this (2026-11-24).
`swift build` compiles an `.xcstrings` declared as a processed resource into an `en.lproj` and an `es.lproj` with `.strings` and `.stringsdict`, plurals included; it needs `defaultLocalization: "en"` in `Package.swift`, and the app only follows the person's language when its own `Info.plist` declares `CFBundleLocalizations` (`en`, `es`), which `build-app.sh` writes; without it the app is English whatever the system says.
Of 30 real sentences of the app, 18 fit the subset as they are, 11 after a small change in the caller (a `switch` becomes a `select`, a sentence built with `+=` becomes one key), and one, the English ordinal "3rd", was reworded; the Swift and TypeScript output was the same in en-US, es-ES and es-AR, line for line, and the generator was about 250 lines with no dependency.
A region that CLDR does not know (English with Uruguay, say) is formatted by each platform its own way, so the shared fixtures use only locales CLDR has.
