import IOBluetooth
import CoreBluetooth
import Combine

struct BluetoothHeadphoneInfo: Equatable {
    var name: String
    var singleBattery: Int?
    var leftBattery: Int?
    var rightBattery: Int?
    var caseBattery: Int?

    var primaryBattery: Int? { singleBattery ?? leftBattery ?? rightBattery }
}

/// Shows a transient HUD (reusing the same pill-based pattern as VolumeObserver/
/// BrightnessObserver) when a Bluetooth headset connects, mimicking iOS's
/// "AirPods connected" popup. Connection detection uses the public IOBluetoothDevice
/// API. Which devices count as "headphones" is decided from the Class of Device
/// (public, Bluetooth-spec-standard bitfield) so this fires for any headset/
/// headphones, not just Apple's — a mouse or keyboard connecting won't trigger it.
/// Per-earbud battery percentages, when available, come from runtime properties
/// AirPods-style devices expose (batteryPercentSingle/Left/Right/Case) that Apple
/// never put in the public header — the same KVC lookup many AirPods-battery menu
/// bar apps use. Third-party headsets that don't expose these just show name + icon.
///
/// Registration only happens while Preferences' "Phát hiện tai nghe Bluetooth"
/// toggle is on — flipping it is what triggers the system Bluetooth permission
/// prompt, not app launch, so nothing is asked for until the user opts in.
final class BluetoothHeadphoneObserver: NSObject, ObservableObject {
    @Published private(set) var connected: BluetoothHeadphoneInfo?
    @Published private(set) var isVisible = false

    private var connectNotification: IOBluetoothUserNotification?
    private var hideWorkItem: DispatchWorkItem?
    private var settingsCancellable: AnyCancellable?

    init(settings: AppSettings) {
        super.init()
        settingsCancellable = settings.$bluetoothHeadphoneDetectionEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in self?.setEnabled(enabled) }
    }

    deinit { connectNotification?.unregister() }

    private func setEnabled(_ enabled: Bool) {
        guard enabled else {
            connectNotification?.unregister()
            connectNotification = nil
            return
        }
        guard connectNotification == nil else { return }

        // If the user denies (or hasn't yet been asked for) Bluetooth access, registering
        // for connect notifications touches IOBluetooth's CoreBluetooth-backed TCC check —
        // skip it entirely so the app just runs without the headphone HUD instead of
        // risking that path. .notDetermined is still allowed through so this first
        // registration is what prompts the user for permission.
        guard Self.isAuthorized else {
            print("[Bluetooth] access not authorized (\(CBManager.authorization)); headphone HUD disabled")
            return
        }

        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(bluetoothDeviceConnected(notification:device:))
        )
    }

    private static var isAuthorized: Bool {
        switch CBManager.authorization {
        case .denied, .restricted: return false
        case .notDetermined, .allowedAlways: return true
        @unknown default: return true
        }
    }

    @objc private func bluetoothDeviceConnected(notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard Self.isHeadsetOrHeadphones(device) else { return }
        // Battery values arrive shortly after the connection completes, not instantly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.show(Self.headphoneInfo(for: device))
        }
    }

    private func show(_ info: BluetoothHeadphoneInfo) {
        connected = info
        isVisible = true

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.isVisible = false }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: workItem)
    }

    /// Class of Device is a 24-bit field (Bluetooth Core Spec, Assigned Numbers):
    /// bits 8-12 = major device class, bits 2-7 = minor device class. Major class
    /// 0x04 is "Audio/Video"; the minor values below are the headset/headphones/
    /// portable-audio/hifi variants within it — this covers AirPods, Beats, and
    /// any generic Bluetooth headphones or headset.
    private static func isHeadsetOrHeadphones(_ device: IOBluetoothDevice) -> Bool {
        let classOfDevice = device.classOfDevice
        let majorClass = (classOfDevice >> 8) & 0x1F
        let minorClass = (classOfDevice >> 2) & 0x3F
        let audioVideoMajorClass: UInt32 = 0x04
        let headsetLikeMinorClasses: Set<UInt32> = [1, 2, 6, 7, 0x0A]
        return majorClass == audioVideoMajorClass && headsetLikeMinorClasses.contains(minorClass)
    }

    private static func headphoneInfo(for device: IOBluetoothDevice) -> BluetoothHeadphoneInfo {
        func battery(_ key: String) -> Int? {
            guard let value = device.value(forKey: key) as? Int, value >= 0 else { return nil }
            return value
        }

        return BluetoothHeadphoneInfo(
            name: device.name ?? "Tai nghe Bluetooth",
            singleBattery: battery("batteryPercentSingle"),
            leftBattery: battery("batteryPercentLeft"),
            rightBattery: battery("batteryPercentRight"),
            caseBattery: battery("batteryPercentCase")
        )
    }
}
