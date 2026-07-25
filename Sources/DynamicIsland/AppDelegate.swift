import Cocoa
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel!
    private let nowPlaying = NowPlayingProvider()
    private let volume = VolumeObserver()
    private let brightness = BrightnessObserver()
    private let bluetoothHeadphones = BluetoothHeadphoneObserver()

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { return }

        let notchWidth = detectedNotchWidth(on: screen)
        let compactHeight = NSStatusBar.system.thickness + 4
        let panelWidth: CGFloat = 420
        let panelHeight: CGFloat = 220

        let originX = screen.frame.midX - panelWidth / 2
        let originY = screen.frame.maxY - panelHeight
        let frame = NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight)

        let hitTestModel = IslandHitTestModel()
        let content = IslandView(
            compactHeight: compactHeight,
            notchWidth: notchWidth,
            hitTestModel: hitTestModel,
            nowPlaying: nowPlaying,
            volume: volume,
            brightness: brightness,
            bluetoothHeadphones: bluetoothHeadphones
        )
        let hostingView = ClickThroughHostingView(rootView: content)
        hostingView.hitTestModel = hitTestModel

        panel = NotchPanel(contentRect: frame)
        panel.contentView = hostingView
        panel.orderFrontRegardless()

        registerAsLoginItem()
    }

    /// Registers this app to launch at login. Only takes effect when running from a
    /// proper .app bundle (see Scripts/build_app.sh) — silently no-ops otherwise.
    private func registerAsLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        try? SMAppService.mainApp.register()
    }

    /// macOS 12+ exposes the rectangles flanking the physical notch.
    /// If unavailable (non-notch Mac), fall back to a sane default so the pill still renders centered.
    private func detectedNotchWidth(on screen: NSScreen) -> CGFloat {
        if #available(macOS 12.0, *),
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            return screen.frame.width - left.width - right.width
        }
        return 200
    }
}
