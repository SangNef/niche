import Cocoa
import Combine

/// Detects whether the frontmost app is currently full screen, so the notch
/// panel can hide itself when Preferences' "Ẩn khi ứng dụng toàn màn hình"
/// toggle is on. There's no public API for "is this window full screen" for
/// windows owned by other apps, so this checks whether the frontmost app's
/// on-screen window (CGWindowListCopyWindowInfo, layer 0) covers the whole
/// screen — the same technique other menu bar utilities use to hide
/// themselves during full screen.
///
/// Tracking only happens while the Preferences toggle is on, mirroring
/// BluetoothHeadphoneObserver's opt-in pattern.
final class FullScreenObserver: ObservableObject {
    @Published private(set) var isFullScreen = false

    private var settingsCancellable: AnyCancellable?
    private var activationObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?
    private var pollTimer: Timer?

    init(settings: AppSettings) {
        settingsCancellable = settings.$disableOnFullScreen
            .removeDuplicates()
            .sink { [weak self] enabled in self?.setEnabled(enabled) }
    }

    deinit { setEnabled(false) }

    private func setEnabled(_ enabled: Bool) {
        let center = NSWorkspace.shared.notificationCenter
        guard enabled else {
            if let activationObserver { center.removeObserver(activationObserver) }
            if let spaceChangeObserver { center.removeObserver(spaceChangeObserver) }
            activationObserver = nil
            spaceChangeObserver = nil
            pollTimer?.invalidate()
            pollTimer = nil
            isFullScreen = false
            return
        }
        guard activationObserver == nil else { return }

        activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.refresh() }
        spaceChangeObserver = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.refresh() }

        // Neither notification fires when a window enters/exits full screen
        // within the same app and space (e.g. the green-button toggle), so a
        // light poll catches that case too.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        refresh()
    }

    private func refresh() {
        isFullScreen = Self.isFrontmostAppFullScreen()
    }

    private static func isFrontmostAppFullScreen() -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main,
              let frontmostApp = NSWorkspace.shared.frontmostApplication,
              let windowListInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }

        let frontmostPID = frontmostApp.processIdentifier
        // CGWindowListCopyWindowInfo bounds are in global display coordinates
        // with (0, 0) at the top-left of the *primary* display (the one with
        // the menu bar) — the same display AppDelegate anchors the notch
        // panel to. That happens to line up with checking the window's
        // origin against (0, 0)..(width, height) directly, with no coordinate
        // flip needed, only for that primary display; a window fullscreen on
        // a secondary monitor will have an origin outside that range even if
        // its size happens to match.
        let screenWidth = screen.frame.width
        let screenHeight = screen.frame.height

        for window in windowListInfo {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t, ownerPID == frontmostPID else { continue }
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = boundsDict["X"], let y = boundsDict["Y"],
                  let width = boundsDict["Width"], let height = boundsDict["Height"]
            else { continue }
            let isOnPrimaryScreen = x > -1 && y > -1 && x < screenWidth && y < screenHeight
            if isOnPrimaryScreen, width >= screenWidth, height >= screenHeight {
                return true
            }
        }
        return false
    }
}
