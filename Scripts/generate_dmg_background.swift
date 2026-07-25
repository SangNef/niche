#!/usr/bin/env swift
// Renders the background image shown behind the icons in the installer DMG
// (dark gradient + arrow pointing from the app icon to the Applications alias).
// Run manually whenever the artwork needs tweaking: it's not part of build_dmg.sh
// so the DMG build stays fast and doesn't need to re-render this every time.
//
//   swift Scripts/generate_dmg_background.swift Resources/dmg-background.png

import AppKit

let width: CGFloat = 660
let height: CGFloat = 400
let size = NSSize(width: width, height: height)

let image = NSImage(size: size)
image.lockFocus()

NSGradient(
    colors: [
        NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0),
        NSColor(calibratedRed: 0.03, green: 0.03, blue: 0.04, alpha: 1.0),
    ]
)?.draw(in: NSRect(origin: .zero, size: size), angle: -90)

// Arrow between the two icon slots (app icon on the left, Applications alias on the right —
// positions here must match APP_ICON_X/APPS_ICON_X in Scripts/build_dmg.sh).
let arrowY: CGFloat = 190
let arrowStart = NSPoint(x: 255, y: arrowY)
let arrowEnd = NSPoint(x: 400, y: arrowY)
let strokeColor = NSColor(calibratedWhite: 1.0, alpha: 0.45)

let shaft = NSBezierPath()
shaft.lineWidth = 4
shaft.lineCapStyle = .round
shaft.move(to: arrowStart)
shaft.line(to: arrowEnd)
strokeColor.setStroke()
shaft.stroke()

let headLength: CGFloat = 14
let head = NSBezierPath()
head.lineWidth = 4
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.move(to: NSPoint(x: arrowEnd.x - headLength, y: arrowEnd.y + headLength))
head.line(to: arrowEnd)
head.line(to: NSPoint(x: arrowEnd.x - headLength, y: arrowEnd.y - headLength))
strokeColor.setStroke()
head.stroke()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let caption = "Kéo Niche vào thư mục Applications để cài đặt"
caption.draw(
    in: NSRect(x: 0, y: 110, width: width, height: 20),
    withAttributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 1.0, alpha: 0.55),
        .paragraphStyle: paragraph,
    ]
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write("Failed to render background image\n".data(using: .utf8)!)
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
try png.write(to: URL(fileURLWithPath: outputPath))
print("Wrote \(outputPath)")
