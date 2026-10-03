import Cocoa
import Combine

/// Watches Caps Lock via NSEvent's global/local flagsChanged monitors (same
/// mechanism as BrightnessObserver's media-key fallback — a passive NSEvent
/// monitor, not a CGEventTap, so no Input Monitoring permission needed) and
/// exposes a transient "just toggled" signal for a HUD pill.
final class CapsLockObserver: ObservableObject {
    @Published private(set) var isOn: Bool
    @Published private(set) var isVisible = false

    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var hideWorkItem: DispatchWorkItem?

    init() {
        isOn = NSEvent.modifierFlags.contains(.capsLock)

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    deinit {
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    }

    private func handle(_ event: NSEvent) {
        let newState = event.modifierFlags.contains(.capsLock)
        guard newState != isOn else { return }
        isOn = newState
        show()
    }

    private func show() {
        isVisible = true
        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.isVisible = false }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: workItem)
    }
}
