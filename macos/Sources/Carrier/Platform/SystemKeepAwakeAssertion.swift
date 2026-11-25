import CarrierCore
import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// The system's power assertions (IOKit): one for the system and one for the display, both the system's own, so they go when the app does and
/// leave nothing behind (no `pmset`, no admin password). Main thread only.
@MainActor final class SystemKeepAwakeAssertion: KeepAwakeAssertion {
    private var ids: [AwakeAssertionKind: IOPMAssertionID] = [:]
    private var source: CFRunLoopSource?
    private var changed: @MainActor () -> Void = {}

    func isHeld(_ kind: AwakeAssertionKind) -> Bool { ids[kind] != nil }

    func take(_ kind: AwakeAssertionKind) -> Bool {
        guard ids[kind] == nil else { return true }
        let type = kind == .system ? kIOPMAssertPreventUserIdleSystemSleep : kIOPMAssertPreventUserIdleDisplaySleep
        var id = IOPMAssertionID(0)
        let made = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), Copy.awakeAssertionReason() as CFString, &id)
        guard made == kIOReturnSuccess else {
            NSLog("Carrier: the Mac could not be kept awake (%@, %d)", type, made)
            return false
        }
        ids[kind] = id
        return true
    }

    func release(_ kind: AwakeAssertionKind) {
        guard let id = ids.removeValue(forKey: kind) else { return }
        IOPMAssertionRelease(id)
    }

    func powerFacts() -> PowerFacts {
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

    /// Once, on the instance that lives as long as the app: the callback holds this object without retaining it, and nothing here is torn down.
    func watchPower(_ changed: @escaping @MainActor () -> Void) {
        guard source == nil else { return }
        self.changed = changed
        let context = Unmanaged.passUnretained(self).toOpaque()
        // fires when the battery's level or the source changes; the common modes keep it coming while the status menu is open
        guard let made = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let assertion = Unmanaged<SystemKeepAwakeAssertion>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { assertion.changed() } }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), made, .commonModes)
        source = made
    }
}
