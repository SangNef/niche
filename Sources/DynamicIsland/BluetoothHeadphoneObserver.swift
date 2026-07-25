import IOBluetooth
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
/// API; per-earbud battery percentages come from runtime properties AirPods-style
/// devices expose (batteryPercentSingle/Left/Right/Case) that Apple never put in the
/// public header — the same kind of KVC lookup many AirPods-battery menu bar apps use.
final class BluetoothHeadphoneObserver: NSObject, ObservableObject {
    @Published private(set) var connected: BluetoothHeadphoneInfo?
    @Published private(set) var isVisible = false

    private var connectNotification: IOBluetoothUserNotification?
    private var hideWorkItem: DispatchWorkItem?

    override init() {
        super.init()
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(bluetoothDeviceConnected(notification:device:))
        )
    }

    deinit { connectNotification?.unregister() }

    @objc private func bluetoothDeviceConnected(notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        // Battery values arrive shortly after the connection completes, not instantly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let info = Self.headphoneInfo(for: device) else { return }
            self?.show(info)
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

    private static func headphoneInfo(for device: IOBluetoothDevice) -> BluetoothHeadphoneInfo? {
        func battery(_ key: String) -> Int? {
            guard let value = device.value(forKey: key) as? Int, value >= 0 else { return nil }
            return value
        }

        let single = battery("batteryPercentSingle")
        let left = battery("batteryPercentLeft")
        let right = battery("batteryPercentRight")
        let caseBattery = battery("batteryPercentCase")

        // No battery properties at all means this isn't an AirPods-style headset —
        // don't show the HUD for every random paired Bluetooth accessory.
        guard single != nil || left != nil || right != nil || caseBattery != nil else { return nil }

        return BluetoothHeadphoneInfo(
            name: device.name ?? "Tai nghe Bluetooth",
            singleBattery: single,
            leftBattery: left,
            rightBattery: right,
            caseBattery: caseBattery
        )
    }
}
