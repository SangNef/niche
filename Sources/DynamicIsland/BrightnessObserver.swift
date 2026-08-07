import AppKit
import CoreGraphics
import Combine

private typealias DisplayServicesGetBrightnessFunction = @convention(c) (
    CGDirectDisplayID, UnsafeMutablePointer<Float>
) -> Int32

// CoreDisplay is the newer, lower-level framework backing the Displays
// preference pane's brightness slider. Recent macOS versions added a
// software-dimming brightness control for external monitors that have no real
// DDC/backlight support at all (so the system's own OSD can still show for
// them) — DisplayServicesGetBrightness above doesn't see that value, but this
// does, since it's what actually enforces it.
private typealias CoreDisplayGetUserBrightnessFunction = @convention(c) (CGDirectDisplayID) -> Double

/// Polls display brightness via private frameworks (same technique as
/// VolumeObserver's CoreAudio usage — no public API exposes this) and exposes a
/// transient "just changed" signal for a HUD pill, mirroring VolumeObserver.
final class BrightnessObserver: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var isVisible = false

    private var timer: Timer?
    private var hideWorkItem: DispatchWorkItem?
    private let getBrightness: DisplayServicesGetBrightnessFunction?
    private let getLinearBrightness: DisplayServicesGetBrightnessFunction?
    private let getCoreDisplayBrightness: CoreDisplayGetUserBrightnessFunction?

    // Tracked per display so a multi-monitor setup (built-in + external, or an
    // external-only Mac) doesn't miss changes on whichever display the brightness
    // keys actually affect.
    private var lastKnownLevels: [CGDirectDisplayID: Float] = [:]

    // Fallback for the rare case where none of the APIs above can read any
    // display's brightness at all: watch the physical brightness keys directly
    // and fake a relative level, just so the HUD still reacts to a key press.
    private static let brightnessStep: Float = 1.0 / 16.0
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    init() {
        getBrightness = Self.loadFunction(
            named: "DisplayServicesGetBrightness", frameworkPath: Self.displayServicesPath
        )
        getLinearBrightness = Self.loadFunction(
            named: "DisplayServicesGetLinearBrightness", frameworkPath: Self.displayServicesPath
        )
        getCoreDisplayBrightness = Self.loadFunction(
            named: "CoreDisplay_Display_GetUserBrightness", frameworkPath: Self.coreDisplayPath
        )

        lastKnownLevels = Self.currentLevelsByDisplay(
            getBrightness: getBrightness,
            getLinearBrightness: getLinearBrightness,
            getCoreDisplayBrightness: getCoreDisplayBrightness
        )
        level = Self.preferredLevel(from: lastKnownLevels)
        if level == 0, lastKnownLevels.isEmpty { level = 0.5 }

        Self.logDiagnostics(
            getBrightness: getBrightness,
            getLinearBrightness: getLinearBrightness,
            getCoreDisplayBrightness: getCoreDisplayBrightness,
            levels: lastKnownLevels
        )

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.poll()
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handleSystemDefinedEvent(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            self?.handleSystemDefinedEvent(event)
            return event
        }
    }

    deinit {
        timer?.invalidate()
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    }

    /// NX_KEYTYPE_BRIGHTNESS_UP / _DOWN delivered as NSSystemDefined events
    /// (subtype 8, "aux control buttons") — the same media-key mechanism apps
    /// like MediaKeyTap use, no Input Monitoring permission required since this
    /// is a passive NSEvent monitor, not a CGEventTap.
    private func handleSystemDefinedEvent(_ event: NSEvent) {
        guard event.subtype.rawValue == 8 else { return }
        let keyCode = Int32((event.data1 & 0xFFFF_0000) >> 16)
        let keyState = (event.data1 & 0x0000_FFFF) >> 8
        guard keyState == 0x0A else { return } // key-down only, ignore key-up/repeat-release
        switch keyCode {
        case 2: nudgeSynthesizedLevel(by: Self.brightnessStep)
        case 3: nudgeSynthesizedLevel(by: -Self.brightnessStep)
        default: break
        }
    }

    /// Only used when no display's real brightness is readable — otherwise the
    /// poll loop above already has ground truth and this would just fight it.
    private func nudgeSynthesizedLevel(by delta: Float) {
        guard lastKnownLevels.isEmpty else { return }
        level = min(max(level + delta, 0), 1)
        show()
    }

    private func poll() {
        let current = Self.currentLevelsByDisplay(
            getBrightness: getBrightness,
            getLinearBrightness: getLinearBrightness,
            getCoreDisplayBrightness: getCoreDisplayBrightness
        )
        guard let changedLevel = Self.changedLevel(from: lastKnownLevels, to: current) else {
            lastKnownLevels = current
            return
        }
        lastKnownLevels = current
        level = changedLevel
        show()
    }

    private func show() {
        isVisible = true
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.isVisible = false }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: workItem)
    }

    /// Reads whatever displays currently support software brightness readback.
    /// The built-in panel almost always does; some external monitors only
    /// surface through CoreDisplay's newer software-dimming path, and a few
    /// (no DDC, no software dimming) are simply skipped rather than reported as 0%.
    private static func currentLevelsByDisplay(
        getBrightness: DisplayServicesGetBrightnessFunction?,
        getLinearBrightness: DisplayServicesGetBrightnessFunction?,
        getCoreDisplayBrightness: CoreDisplayGetUserBrightnessFunction?
    ) -> [CGDirectDisplayID: Float] {
        var result: [CGDirectDisplayID: Float] = [:]
        for displayID in activeDisplayIDs() {
            if let value = readBrightness(displayID, using: getBrightness)
                ?? readBrightness(displayID, using: getLinearBrightness)
                ?? readCoreDisplayBrightness(displayID, using: getCoreDisplayBrightness) {
                result[displayID] = value
            }
        }
        return result
    }

    private static func readBrightness(
        _ displayID: CGDirectDisplayID, using function: DisplayServicesGetBrightnessFunction?
    ) -> Float? {
        guard let function else { return nil }
        var value: Float = 0
        let status = function(displayID, &value)
        return status == 0 ? value : nil
    }

    private static func readCoreDisplayBrightness(
        _ displayID: CGDirectDisplayID, using function: CoreDisplayGetUserBrightnessFunction?
    ) -> Float? {
        guard let function else { return nil }
        let value = function(displayID)
        // No status code on this one — a display with no brightness control at
        // all reports back exactly 0, which we treat as "unsupported" rather
        // than "brightness is 0%" (nothing meaningfully hits true zero here).
        guard value > 0 else { return nil }
        return Float(value)
    }

    private static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else { return [] }
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount) == .success else { return [] }
        return displayIDs
    }

    /// Picks whichever tracked display actually moved since the last poll —
    /// there's normally only one (the one the brightness keys affect).
    private static func changedLevel(
        from previous: [CGDirectDisplayID: Float], to current: [CGDirectDisplayID: Float]
    ) -> Float? {
        for (displayID, newValue) in current {
            guard let oldValue = previous[displayID] else { continue }
            if abs(newValue - oldValue) > 0.001 { return newValue }
        }
        return nil
    }

    /// Startup value: prefer the built-in display if one is readable, otherwise
    /// whatever the first readable display reports.
    private static func preferredLevel(from levels: [CGDirectDisplayID: Float]) -> Float {
        if let builtIn = levels.first(where: { CGDisplayIsBuiltin($0.key) != 0 }) {
            return builtIn.value
        }
        return levels.values.first ?? 0
    }

    /// One-time startup dump so a "brightness HUD doesn't show" report can be
    /// diagnosed from the log instead of guessing: which displays macOS sees,
    /// whether each private API loaded, and which displays are readable.
    private static func logDiagnostics(
        getBrightness: DisplayServicesGetBrightnessFunction?,
        getLinearBrightness: DisplayServicesGetBrightnessFunction?,
        getCoreDisplayBrightness: CoreDisplayGetUserBrightnessFunction?,
        levels: [CGDirectDisplayID: Float]
    ) {
        print("[Brightness] DisplayServicesGetBrightness loaded: \(getBrightness != nil)")
        print("[Brightness] DisplayServicesGetLinearBrightness loaded: \(getLinearBrightness != nil)")
        print("[Brightness] CoreDisplay_Display_GetUserBrightness loaded: \(getCoreDisplayBrightness != nil)")
        let displays = activeDisplayIDs()
        print("[Brightness] active displays: \(displays.count)")
        for displayID in displays {
            let builtIn = CGDisplayIsBuiltin(displayID) != 0
            if let level = levels[displayID] {
                print("[Brightness]  - display \(displayID) (builtin: \(builtIn)): readable, level=\(level)")
            } else {
                print("[Brightness]  - display \(displayID) (builtin: \(builtIn)): NOT readable via any API")
            }
        }
        fflush(stdout)
    }

    private static let displayServicesPath = "/System/Library/PrivateFrameworks/DisplayServices.framework"
    private static let coreDisplayPath = "/System/Library/PrivateFrameworks/CoreDisplay.framework"

    private static func loadFunction<T>(named name: String, frameworkPath: String) -> T? {
        guard let bundle = CFBundleCreate(kCFAllocatorDefault, NSURL(fileURLWithPath: frameworkPath))
        else { return nil }

        guard let pointer = CFBundleGetFunctionPointerForName(bundle, name as CFString) else { return nil }

        return unsafeBitCast(pointer, to: T.self)
    }
}
