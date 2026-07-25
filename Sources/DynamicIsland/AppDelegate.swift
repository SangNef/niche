import Cocoa
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel!
    private var clickThroughTimer: Timer?
    private var statusItem: NSStatusItem?
    private let nowPlaying = NowPlayingProvider()
    private let volume = VolumeObserver()
    private let brightness = BrightnessObserver()
    private let bluetoothHeadphones = BluetoothHeadphoneObserver()
    private let updateChecker = UpdateChecker()

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePanel()
        setupStatusItem()
        startClickThroughTracking()
        registerAsLoginItem()

        // Reconfigure when displays are connected/disconnected/rearranged, so the
        // pill follows whichever screen is primary instead of staying stuck on
        // whatever screen was primary at launch.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        configurePanel()
    }

    /// Rebuilds the panel's frame and content for the current primary screen.
    private func configurePanel() {
        guard let screen = Self.primaryScreen() else { return }

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
            bluetoothHeadphones: bluetoothHeadphones,
            updateChecker: updateChecker
        )
        let hostingView = ClickThroughHostingView(rootView: content)
        hostingView.hitTestModel = hitTestModel

        if let panel {
            panel.setFrame(frame, display: true)
        } else {
            panel = NotchPanel(contentRect: frame)
            panel.orderFrontRegardless()
        }
        panel.contentView = hostingView
    }

    /// The screen containing the menu bar always sits at the global coordinate
    /// system's origin — per AppKit convention, regardless of how many displays are
    /// connected or how they're arranged. More reliable than NSScreen.main, which
    /// resolves via the key window, and this app's non-activating panel never
    /// becomes key.
    private static func primaryScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// The panel's content rect is a fixed 420x220 box, but the visible pill is
    /// usually much smaller — polling the cursor position lets us only "claim" mouse
    /// events (via ignoresMouseEvents) while it's actually over the pill, so the rest
    /// of that box stays click-through to whatever's underneath. Polls at 60Hz rather
    /// than relying on this window's own mouse-moved events, since ignoresMouseEvents
    /// = true makes it stop receiving those entirely while the cursor is outside —
    /// NSEvent.mouseLocation works regardless of which window owns the cursor.
    private func startClickThroughTracking() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateIgnoresMouseEvents()
        }
        RunLoop.main.add(timer, forMode: .common)
        clickThroughTimer = timer
    }

    private func updateIgnoresMouseEvents() {
        guard let panel, let contentView = panel.contentView else { return }
        let mouseLocationInWindow = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let isOverPill = contentView.hitTest(mouseLocationInWindow) != nil
        panel.ignoresMouseEvents = !isOverPill
    }

    /// LSUIElement apps have no Dock icon, which also means no entry in the standard
    /// Force Quit Applications window (⌘⌥Esc) — that only lists apps with a Dock
    /// presence. This menu bar item is the escape hatch: a one-click way to quit if
    /// something goes wrong, without needing Activity Monitor or Terminal.
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = Self.menuBarIcon()
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Niche", action: #selector(quitApp), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
    }

    /// A monochrome glyph echoing the app icon's pill-with-two-dots shape, drawn in
    /// code rather than shipped as an asset. Marked as a template image so AppKit
    /// tints it gray/white/highlighted to match every other menu bar icon (Wi-Fi,
    /// Bluetooth, ...) automatically in light and dark mode — the full-color app icon
    /// can't do that since template rendering just fills its alpha shape solid.
    private static func menuBarIcon() -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let capsuleRect = rect.insetBy(dx: 1, dy: 5)
            let capsule = NSBezierPath(
                roundedRect: capsuleRect,
                xRadius: capsuleRect.height / 2,
                yRadius: capsuleRect.height / 2
            )
            capsule.lineWidth = 1.3
            NSColor.black.setStroke()
            capsule.stroke()

            NSColor.black.setFill()
            let dotSize: CGFloat = 3
            let dotY = capsuleRect.midY - dotSize / 2
            let firstDotX = capsuleRect.minX + 3.5
            NSBezierPath(ovalIn: NSRect(x: firstDotX, y: dotY, width: dotSize, height: dotSize)).fill()
            NSBezierPath(ovalIn: NSRect(x: firstDotX + dotSize + 2, y: dotY, width: dotSize, height: dotSize)).fill()

            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
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
