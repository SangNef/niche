import Cocoa
import SwiftUI

/// Tracks where the visible pill currently is, in the hosting window's coordinate space.
/// Used so the transparent parts of the panel let mouse clicks pass through to apps below.
final class IslandHitTestModel: ObservableObject {
    @Published var frameInWindow: CGRect = .zero
}

/// NSHostingView that only accepts mouse events inside the pill's current bounds.
/// Everywhere else in the (otherwise invisible) panel is click-through.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    var hitTestModel: IslandHitTestModel?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let frame = hitTestModel?.frameInWindow, frame.contains(point) else {
            return nil
        }
        return super.hitTest(point)
    }
}
