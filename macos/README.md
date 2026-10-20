# Carrier.app

Menu bar app for Carrier. A SwiftPM package for macOS 13 or later: `CarrierCore` (library), `Carrier` (the AppKit shell), `CarrierCoreTests` and `CarrierTests` (Swift Testing). The Command Line Tools are enough, Xcode is not needed.

## Build and open

```sh
cd macos
./build-app.sh          # release build wrapped in Carrier.app (bundle id dev.ashulab.carrier), signed ad hoc
./build-app.sh --open   # same, then opens it
open Carrier.app
```

`Carrier.app` has no Dock icon: it shows one menu bar item. Its menu has a line saying whether Carrier is stopped, running (epics and busy/total slots) or an incompatible version, and Quit. The line comes from Carrier's control socket, `<root>/orchestrator/control.sock`, where `<root>` is the `root` of `$CARRIER_HOME/config.json` (else `~/.carrier/config.json`), `~/.solve` when there is none; the app asks for the snapshot every second while connected and tries to connect every three seconds while not. Check the signature with `codesign --verify Carrier.app` and `codesign -dv Carrier.app` (it should say `Signature=adhoc`).

## Test

```sh
cd macos
swift build && swift test
```

The shell's layers have no automated tests (`CarrierTests` only checks that the icon's layer host takes no clicks). Its smoke check is the self-test flag: it runs the menu's actions from code, one a second, appends a line per step to the file and ends with a line saying the process was still alive.

```sh
./Carrier.app/Contents/MacOS/Carrier --selftest /tmp/carrier-selftest.log
cat /tmp/carrier-selftest.log   # last line: "end: process still alive ..."
```

The app keeps running afterwards; quit it from the menu or with `osascript -e 'tell application id "dev.ashulab.carrier" to quit'`.
