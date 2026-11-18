import AppKit
import CarrierCore
import IOKit.ps
import IOKit.pwr_mgt

/// Keeps the Mac from sleeping (docs/macos/keep-awake.md). One power assertion for the system, and one for the display when the person
/// asked for the screen too: both are the system's own, so they go when the app does and leave nothing behind (no `pmset`, no admin password).
/// What to hold is decided by `awakeDecision` from what the person asked, what the agents do and the battery; this class only feeds it
/// and acts on the answer. Closing the lid still sleeps the Mac: an assertion cannot stop that. Main thread only.
@MainActor @Observable final class KeepAwakeController {
    static let shared = KeepAwakeController()

    /// What the person asked for by hand, and the length it was asked with (to check it in the menu).
    private(set) var manual: AwakeManual?
    private(set) var manualMinutes = AwakeLength.defaultMinutes
    private(set) var decision = AwakeDecision()
    private(set) var power = PowerFacts(onBattery: false, percent: nil)
    private(set) var settings = AwakeSettings()
    /// Why the recorded shortcut is not registered (another app or Carrier itself holds it); nil when it is, or none is recorded.
    private(set) var shortcutProblem: String?

    @ObservationIgnored private var epicsWorking = 0
    @ObservationIgnored private var sessionsWorking = 0
    @ObservationIgnored private var lastWorked: Date?
    @ObservationIgnored private var systemAssertion = IOPMAssertionID(0)
    @ObservationIgnored private var displayAssertion = IOPMAssertionID(0)
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var hotKey: GlobalHotKey?
    /// The shortcut that is registered, and the one the system refused (not tried again until the keys are recorded or Carrier comes back to the front).
    @ObservationIgnored private var registered: DictationShortcut?
    @ObservationIgnored private var refused: DictationShortcut?
    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private var started = false
    /// The Settings recorder listens: the registered shortcut is let go, so pressing it records it and does not toggle.
    @ObservationIgnored var recordingShortcut = false { didSet { registerShortcut() } }
    /// Where the menu bar icon hears of a change.
    @ObservationIgnored var onChange: (AwakeDecision) -> Void = { _ in }
    /// Where a stop by itself is told; the tests and the self-test put their own.
    @ObservationIgnored var notify: (String, String) -> Void = { title, body in
        SystemNotificationCentre.shared.post([EpicNotification(title: title, body: body, sound: false, always: true)])
    }
    @ObservationIgnored var now: () -> Date = Date.init
    /// How the Mac is powered; the tests say their own.
    @ObservationIgnored var readPower: () -> PowerFacts = { KeepAwakeController.systemPower() }
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferences = AppPreferences(defaults: defaults)
    }

    /// Whether the system's assertion is held now, and the display's.
    var holdsSystem: Bool { systemAssertion != 0 }
    var holdsDisplay: Bool { displayAssertion != 0 }

    var working: Bool { epicsWorking + sessionsWorking > 0 }

    /// Reads the settings and the battery, watches both, registers the shortcut. Called once when the app opens, on the shared instance only:
    /// the battery's callback holds this object without retaining it, and nothing here is torn down.
    func start() {
        guard started == false else { return }
        started = true
        power = readPower()
        let context = Unmanaged.passUnretained(self).toOpaque()
        // fires when the battery's level or the source changes; the common modes keep it coming while the status menu is open
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let controller = Unmanaged<KeepAwakeController>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { controller.powerChanged() } }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            powerSource = source
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
        // coming back to the front tries again a shortcut that was refused: the other app may have let it go
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refused = nil
                self?.registerShortcut()
            }
        }
        settingsChanged()
    }

    // MARK: what the person does

    /// Starts a manual keep awake of `minutes` (0 is until turned off), or replaces the one that runs.
    func start(minutes: Int) {
        let length = AwakeLength.valid(minutes)
        manualMinutes = length
        manual = length == 0 ? .indefinite : .until(now().addingTimeInterval(Double(length) * 60))
        refresh()
        // asked for and not holding (the battery's rule): the menu closes on nothing, so it is said
        if let blocked = decision.blocked {
            let notice = awakeWaitingNotice(blocked)
            notify(notice.title, notice.body)
        }
    }

    /// Stops what was asked for by hand. The agents' own keep awake, when it is on, goes on.
    func stopManual() {
        manual = nil
        refresh(silent: true)
    }

    /// The menu's first item and the shortcut: stop what runs by hand, or start the default length.
    func toggle() {
        if decision.isManual { stopManual() } else { start(minutes: settings.defaultMinutes) }
    }

    /// The switch "While agents work", from the menu or from the page.
    func setFollowsAgents(_ on: Bool) {
        defaults.set(on, forKey: AppPreferences.awakeAgentsKey)
        settingsChanged()
    }

    // MARK: what feeds it

    /// The epics that run, from the engine's snapshot.
    func epics(working count: Int) {
        epicsWorking = count
        workChanged()
    }

    /// The chat sessions that work, from the host's list.
    func sessions(working count: Int) {
        sessionsWorking = count
        workChanged()
    }

    private func workChanged() {
        if working { lastWorked = now() }
        refresh()
    }

    func settingsChanged() {
        let read = preferences.awake
        if read != settings {
            settings = read
            // the person changed it: that is not a stop by itself
            refresh(silent: true)
        }
        registerShortcut()
    }

    func powerChanged() {
        let read = readPower()
        guard read != power else { return }
        power = read
        refresh()
    }

    // MARK: acting on the answer

    func refresh(silent: Bool = false) {
        let before = decision
        if case .until(let end)? = manual, end <= now() { manual = nil }
        let next = awakeDecision(now: now(), manual: manual, settings: settings, agentsWorking: working, lastWorked: lastWorked, power: power)
        decision = next
        apply(next)
        scheduleTimer(next)
        if next != before {
            onChange(next)
            // an end after agents finished is the ordinary one and says nothing; a manual end and the battery's are told
            let ordinary = before.isManual == false && next.blocked == nil
            if before.holds, next.holds == false, silent == false, ordinary == false, settings.notifies { tell(next) }
        }
    }

    /// It stopped by itself (the time ran out, or the battery said so) and the person did not do it: say so, or the Mac would just sleep.
    private func tell(_ next: AwakeDecision) {
        let notice = awakeEndedNotice(next.blocked)
        notify(notice.title, notice.body)
    }

    private func apply(_ decision: AwakeDecision) {
        hold(&systemAssertion, kIOPMAssertPreventUserIdleSystemSleep, on: decision.holds)
        hold(&displayAssertion, kIOPMAssertPreventUserIdleDisplaySleep, on: decision.holds && settings.keepsScreenOn)
    }

    private func hold(_ id: inout IOPMAssertionID, _ type: String, on: Bool) {
        switch (on, id != 0) {
        case (true, false):
            let made = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Carrier keeps the Mac awake" as CFString, &id)
            if made != kIOReturnSuccess {
                id = 0
                NSLog("Carrier: the Mac could not be kept awake (%@, %d)", type, made)
            }
        case (false, true):
            IOPMAssertionRelease(id)
            id = 0
        default: break
        }
    }

    /// Wakes at the moment the answer changes by itself (a manual end, the end of the grace).
    private func scheduleTimer(_ decision: AwakeDecision) {
        timer?.invalidate()
        timer = nil
        guard let change = nextAwakeChange(decision) else { return }
        let timer = Timer(fire: change.addingTimeInterval(0.2), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: the shortcut

    private func registerShortcut() {
        let wanted = recordingShortcut ? nil : preferences.awakeShortcut
        if recordingShortcut { refused = nil }
        guard wanted != registered, wanted == nil || wanted != refused else { return }
        hotKey = nil
        registered = nil
        shortcutProblem = nil
        guard let wanted else { return }
        let key = GlobalHotKey(GlobalHotKey.Shortcut(wanted), pressed: { [weak self] in
            MainActor.assumeIsolated { self?.toggle() }
        })
        // the system said no (another app, or Carrier's own Dictation, holds the keys): nothing is shown as active, and the page says why
        guard let key else {
            refused = wanted
            shortcutProblem = "\(wanted.text) is held by another app. Record other keys."
            return
        }
        hotKey = key
        registered = wanted
    }

    // MARK: the battery

    private static func systemPower() -> PowerFacts {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return PowerFacts(onBattery: false, percent: nil) }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let sources = (IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]) ?? []
        var percent: Int?
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = description[kIOPSCurrentCapacityKey] as? Int, let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            percent = current * 100 / maximum
        }
        return PowerFacts(onBattery: providing == kIOPSBatteryPowerValue, percent: percent)
    }
}
