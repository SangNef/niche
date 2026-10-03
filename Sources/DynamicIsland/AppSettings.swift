import Combine
import Foundation
import ServiceManagement

/// Persisted user preferences (UserDefaults-backed) — the single source of truth for
/// anything configurable from the Preferences window. Other parts of the app read
/// these instead of hardcoding the behavior, so a change here takes effect live.
final class AppSettings: ObservableObject {
    private enum Keys {
        static let launchAtLogin = "launchAtLogin"
        static let hoverExpandDelay = "hoverExpandDelay"
        static let pauseHideDelay = "pauseHideDelay"
        static let checkForUpdatesAutomatically = "checkForUpdatesAutomatically"
        static let bluetoothHeadphoneDetectionEnabled = "bluetoothHeadphoneDetectionEnabled"
        static let browserTabJumpEnabled = "browserTabJumpEnabled"
        static let disableOnFullScreen = "disableOnFullScreen"
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin)
            syncLoginItem()
        }
    }
    @Published var hoverExpandDelay: Double {
        didSet { UserDefaults.standard.set(hoverExpandDelay, forKey: Keys.hoverExpandDelay) }
    }
    @Published var pauseHideDelay: Double {
        didSet { UserDefaults.standard.set(pauseHideDelay, forKey: Keys.pauseHideDelay) }
    }
    @Published var checkForUpdatesAutomatically: Bool {
        didSet { UserDefaults.standard.set(checkForUpdatesAutomatically, forKey: Keys.checkForUpdatesAutomatically) }
    }
    /// Off by default — enabling this is what triggers the Bluetooth permission
    /// prompt (see BluetoothHeadphoneObserver), not app launch.
    @Published var bluetoothHeadphoneDetectionEnabled: Bool {
        didSet {
            UserDefaults.standard.set(bluetoothHeadphoneDetectionEnabled, forKey: Keys.bluetoothHeadphoneDetectionEnabled)
        }
    }
    /// Off by default — enabling this is what triggers the per-browser Automation
    /// permission prompt (see BrowserTabLocator), not tapping the pill.
    @Published var browserTabJumpEnabled: Bool {
        didSet { UserDefaults.standard.set(browserTabJumpEnabled, forKey: Keys.browserTabJumpEnabled) }
    }
    /// When on, the notch panel hides itself while the frontmost app is full
    /// screen (see FullScreenObserver) instead of staying on top of it.
    @Published var disableOnFullScreen: Bool {
        didSet { UserDefaults.standard.set(disableOnFullScreen, forKey: Keys.disableOnFullScreen) }
    }

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.launchAtLogin: true,
            Keys.hoverExpandDelay: 0.2,
            Keys.pauseHideDelay: 15.0,
            Keys.checkForUpdatesAutomatically: true,
            Keys.bluetoothHeadphoneDetectionEnabled: false,
            Keys.browserTabJumpEnabled: false,
            Keys.disableOnFullScreen: false,
        ])
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        hoverExpandDelay = defaults.double(forKey: Keys.hoverExpandDelay)
        pauseHideDelay = defaults.double(forKey: Keys.pauseHideDelay)
        checkForUpdatesAutomatically = defaults.bool(forKey: Keys.checkForUpdatesAutomatically)
        bluetoothHeadphoneDetectionEnabled = defaults.bool(forKey: Keys.bluetoothHeadphoneDetectionEnabled)
        browserTabJumpEnabled = defaults.bool(forKey: Keys.browserTabJumpEnabled)
        disableOnFullScreen = defaults.bool(forKey: Keys.disableOnFullScreen)
    }

    /// Registers/unregisters the login item to match `launchAtLogin`. Call once at
    /// launch to correct any drift (e.g. the user removed it via System Settings)
    /// and again whenever the Preferences toggle changes.
    func syncLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("[Settings] failed to \(launchAtLogin ? "register" : "unregister") login item: \(error)")
        }
    }
}
