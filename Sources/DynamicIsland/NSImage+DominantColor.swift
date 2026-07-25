import AppKit
import CoreImage

extension NSImage {
    /// Average color of the image, computed via CIAreaAverage — cheap enough to run
    /// once per track change and good enough to tint a small equalizer icon.
    func averageColor() -> NSColor? {
        guard let tiffData = tiffRepresentation, let ciImage = CIImage(data: tiffData) else { return nil }

        let extent = CIVector(
            x: ciImage.extent.origin.x, y: ciImage.extent.origin.y,
            z: ciImage.extent.size.width, w: ciImage.extent.size.height
        )
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: extent
        ]), let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            outputImage, toBitmap: &bitmap, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil
        )

        return NSColor(
            red: CGFloat(bitmap[0]) / 255,
            green: CGFloat(bitmap[1]) / 255,
            blue: CGFloat(bitmap[2]) / 255,
            alpha: 1
        )
    }
}

extension NSColor {
    /// Raw average colors from album art tend to look muddy/gray; nudge saturation
    /// and brightness up so the accent still reads as "the artwork's color" but pops.
    func vibrant() -> NSColor {
        guard let converted = usingColorSpace(.deviceRGB) else { return self }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        converted.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: max(saturation, 0.55), brightness: max(brightness, 0.65), alpha: 1)
    }
}
