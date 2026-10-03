import Cocoa
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NotchPanel!
    private var clickThroughTimer: Timer?
    private var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?
    private var fullScreenCancellable: AnyCancellable?

    private let settings = AppSettings()
    private let volume = VolumeObserver()
    private let brightness = BrightnessObserver()
    private let battery = BatteryObserver()
    private let capsLock = CapsLockObserver()
    private let nowPlaying: NowPlayingProvider
    private let updateChecker: UpdateChecker
    private let bluetoothHeadphones: BluetoothHeadphoneObserver
    private let fullScreenObserver: FullScreenObserver

    override init() {
        nowPlaying = NowPlayingProvider(settings: settings)
        updateChecker = UpdateChecker(settings: settings)
        bluetoothHeadphones = BluetoothHeadphoneObserver(settings: settings)
        fullScreenObserver = FullScreenObserver(settings: settings)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePanel()
        setupStatusItem()
        startClickThroughTracking()
        settings.syncLoginItem()

        fullScreenCancellable = fullScreenObserver.$isFullScreen
            .removeDuplicates()
            .sink { [weak self] isFullScreen in self?.updatePanelVisibility(hiddenByFullScreen: isFullScreen) }

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

    /// Orders the panel out while the frontmost app is full screen (when the
    /// user has opted into "Ẩn khi ứng dụng toàn màn hình"), and back in once
    /// it isn't — instead of relying on `.fullScreenAuxiliary`, which keeps
    /// the panel visible in full screen Spaces by default.
    private func updatePanelVisibility(hiddenByFullScreen: Bool) {
        guard let panel else { return }
        if hiddenByFullScreen {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
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
            battery: battery,
            capsLock: capsLock,
            bluetoothHeadphones: bluetoothHeadphones,
            updateChecker: updateChecker,
            settings: settings
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
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Niche", action: #selector(quitApp), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
    }

    @objc private func showPreferences() {
        if preferencesWindow == nil {
            let view = PreferencesView(settings: settings, updateChecker: updateChecker)
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Niche Preferences"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 640, height: 460))
            window.center()
            preferencesWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        preferencesWindow?.makeKeyAndOrderFront(nil)
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
