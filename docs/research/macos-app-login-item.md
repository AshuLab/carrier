# Starting the macOS app at login from the ad-hoc signed `Carrier.app`

> Spike from 2026-10-21 for story 6 of the [macOS app redesign](../specs/macos-app-redesign.md). Closes the open question left in [macos-app-swiftui.md](macos-app-swiftui.md) (question 9). Run on macOS 27.0 (build 26A428), Xcode toolchain, Apple Swift 6.4.

## Short answer

`SMAppService.mainApp.register()` works with the ad-hoc signed bundle that `macos/build-app.sh` produces. No Developer ID, no team, no entitlement and no install into `/Applications` was needed: the test bundle sat in a temp directory.

## How it was run

`build-app.sh` was run on a scratch copy of `macos/` and it built and signed `Carrier.app` (`flags=0x2(adhoc)`, `TeamIdentifier=not set`, id `dev.ashulab.carrier`). The app has no code that calls `SMAppService` yet, so the executable inside a copy of that bundle was swapped for a 20-line probe (the code below, with a command-line argument) and the bundle was signed ad hoc again with the same `codesign --force --sign -` the script uses. Same `Info.plist`, same bundle id. Everything lived under the system temp dir and was deleted afterwards.

## What came back

| Step | Return | `status` afterwards |
|---|---|---|
| `status`, bundle never registered | n/a | `notFound` (3) |
| `register()` | no error | `enabled` (1) |
| `register()` again | no error | `enabled` |
| `unregister()` | no error | `notRegistered` (0) |
| `unregister()` again | no error | `notRegistered` |
| `status` from the bare executable (no bundle) | n/a | `notFound` (3) |

- `notFound` before the first `register()` does not mean it will fail. A bundle that was never registered reads `notFound` on this macOS version and `register()` then succeeds. So the toggle must not be disabled on `notFound`; try `register()` and read `status` again.
- `requiresApproval` (2) was not seen, and was not provoked: it needs the user to switch the entry off in System Settings, which is a click only a person can do. It is documented as "registered but the user has to approve it".
- Rebuilding with a new ad-hoc signature (a changed binary, so a new CDHash: `e476d0ff...` to `5b4a930a...`, signed again with `codesign --force --sign -`) changed nothing: the registration stayed `enabled`, and `register()` on the new build returned `enabled` with no error.
- The registration followed the bundle id, not the path: a copy of the bundle at another path read `enabled`, kept reading `enabled` after the original was deleted, and `unregister()` from the copy cleared it. `register()` was not called from the copy.
- Not tried: a bundle with a different bundle id, a signature that changes the bundle id, a moved bundle that is then deleted before `unregister()` (the entry would then be orphaned and `unregister()` could not be reached from the app), and a reboot with the app registered.

## What Login Items shows

Not verified here. Listing the entries needs either `sfltool dumpbtm` (asks for an administrator password) or System Events scripting (a permission prompt), and neither was done. Reading System Settings, General, Login Items is one of the checks left to a person while a registration is on; the expected name comes from `CFBundleName` (`Carrier`).

## Minimal Swift that worked

```swift
import ServiceManagement

let service = SMAppService.mainApp
try service.register()     // or try service.unregister()
let on = service.status == .enabled
```

`register()` and `unregister()` throw `NSError`; `status` is read, not cached. The on/off switch in Settings should be driven by `status`, never by a stored flag, because the user can change it in System Settings.

## What to show

| `status` | Switch | Text and action |
|---|---|---|
| `enabled` | On | Nothing more. |
| `notRegistered` | Off | Nothing more. |
| `requiresApproval` | Off, with a notice | "Carrier is waiting for your approval in Login Items", with a button calling `SMAppService.openSystemSettingsLoginItems()`. |
| `notFound` | Off | A normal off switch, since this is the state of a bundle that was never registered. Turning it on calls `register()`; if that throws, show the error text under the switch and read `status` again. If it still reads `notFound` after a successful `register()`, say "Carrier can't register itself from here, move it to /Applications and try again". That last branch was not reproduced. |

`notFound` is also what `swift run` and the unit tests see (no bundle), so the toggle has to be hidden or disabled there and only tested from the built `Carrier.app`.

## Leaving it clean

The spike ended with `unregister()` and `status` reading `notRegistered`. To check on any machine: build the bundle, and from its executable read `SMAppService.mainApp.status`; `notRegistered` or `notFound` means nothing is registered, `enabled` or `requiresApproval` means an entry is left. The entry can also be removed by hand in System Settings, General, Login Items (Open at Login list). The Background Task Management list (`sudo sfltool dumpbtm`) was not read, so a stale row there is not ruled out; the status API reported clean.
