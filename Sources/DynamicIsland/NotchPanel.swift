import Cocoa

/// Borderless, non-activating, always-on-top panel anchored at the notch.
/// Fully transparent background so only the SwiftUI-drawn pill is visible.
/// The window's content rect is a fixed 420x220 box (big enough for the expanded
/// hover state), but the visible pill inside it is usually much smaller — so
/// `ignoresMouseEvents` starts true (fully click-through) and AppDelegate's mouse
/// tracker flips it to false only while the cursor is actually over the pill's
/// current bounds. Without that, the whole 420x220 box would swallow clicks meant
/// for whatever's underneath it (SwiftUI's hitTest returning nil only stops this
/// view from handling the event — it doesn't pass it through to the window below).
final class NotchPanel: NSPanel {
    convenience init(contentRect: NSRect) {
        self.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
