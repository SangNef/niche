import IOKit.ps
import Combine

/// Watches the Mac's own battery/power-adapter state via IOKit's power-source
/// API (no polling — IOPS delivers a callback whenever anything about power
/// sources changes) and exposes a transient "just changed" signal, mirroring
/// VolumeObserver/BrightnessObserver's HUD pattern. On a desktop Mac (no
/// battery) `IOPSCopyPowerSourcesList` simply comes back empty, so `update`
/// no-ops and this HUD never fires — no special-casing needed.
final class BatteryObserver: ObservableObject {
    @Published private(set) var percentage: Int = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var isVisible = false

    private var runLoopSource: CFRunLoopSource?
    private var hideWorkItem: DispatchWorkItem?

    // nil until the first read, so that first read can seed state without
    // flashing the HUD for "no prior state" being treated as a change.
    private var lastIsCharging: Bool?
    private var lastIsPluggedIn: Bool?

    init() {
        update(showHUD: false)

        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let observer = Unmanaged<BatteryObserver>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { observer.update(showHUD: true) }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
    }

    private func update(showHUD: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
        else { return }

        let capacity = description[kIOPSCurrentCapacityKey] as? Int ?? percentage
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        let pluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

        let chargingChanged = lastIsCharging.map { $0 != charging } ?? false
        let pluggedChanged = lastIsPluggedIn.map { $0 != pluggedIn } ?? false
        let hasPriorState = lastIsCharging != nil

        percentage = capacity
        isCharging = charging
        isPluggedIn = pluggedIn
        lastIsCharging = charging
        lastIsPluggedIn = pluggedIn

        if showHUD, hasPriorState, chargingChanged || pluggedChanged {
            show()
        }
    }

    private func show() {
        isVisible = true
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.isVisible = false }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }
}
