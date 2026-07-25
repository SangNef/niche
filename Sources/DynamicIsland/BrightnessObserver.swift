import Foundation
import CoreGraphics
import Combine

private typealias DisplayServicesGetBrightnessFunction = @convention(c) (
    CGDirectDisplayID, UnsafeMutablePointer<Float>
) -> Int32

/// Polls the built-in display's brightness via the private DisplayServices framework
/// (same technique as VolumeObserver's CoreAudio usage — no public API exposes this)
/// and exposes a transient "just changed" signal for a HUD pill, mirroring VolumeObserver.
final class BrightnessObserver: ObservableObject {
    @Published private(set) var level: Float = 0
    @Published private(set) var isVisible = false

    private var timer: Timer?
    private var hideWorkItem: DispatchWorkItem?
    private let getBrightness: DisplayServicesGetBrightnessFunction?
    private var lastKnownLevel: Float?

    init() {
        getBrightness = Self.loadFunction()
        lastKnownLevel = currentBrightness()
        level = lastKnownLevel ?? 0

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    deinit { timer?.invalidate() }

    private func poll() {
        guard let newLevel = currentBrightness() else { return }
        guard abs(newLevel - (lastKnownLevel ?? -1)) > 0.001 else { return }
        lastKnownLevel = newLevel
        level = newLevel
        isVisible = true

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.isVisible = false }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: workItem)
    }

    private func currentBrightness() -> Float? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        let status = getBrightness(CGMainDisplayID(), &value)
        return status == 0 ? value : nil
    }

    private static func loadFunction() -> DisplayServicesGetBrightnessFunction? {
        guard let bundle = CFBundleCreate(
            kCFAllocatorDefault,
            NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/DisplayServices.framework")
        ) else { return nil }

        guard let pointer = CFBundleGetFunctionPointerForName(
            bundle, "DisplayServicesGetBrightness" as CFString
        ) else { return nil }

        return unsafeBitCast(pointer, to: DisplayServicesGetBrightnessFunction.self)
    }
}
