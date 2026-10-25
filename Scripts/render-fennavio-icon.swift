#!/usr/bin/env swift
import AppKit

// Native vector source for Fennavio's independently drawn window-F artwork.
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let catalog = repository.appendingPathComponent("CrestShared/Resources/FennavioAssets.xcassets")
let appIcon = catalog.appendingPathComponent("Fennavio.appiconset")
let preview = catalog.appendingPathComponent("FennavioPreview.imageset")

// MARK: - Actions - Rendering

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 255) / 255,
        green: CGFloat((hex >> 8) & 255) / 255,
        blue: CGFloat(hex & 255) / 255,
        alpha: 1)
}

func rectangle(_ bounds: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
}

func render(size: Int, rounded: Bool, margin: CGFloat = 0, to url: URL) throws {
    guard
        let image = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
            samplesPerPixel: rounded ? 4 : 3, hasAlpha: rounded, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
    else { preconditionFailure("The icon bitmap must be allocatable.") }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
    NSGraphicsContext.current?.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
    let transform = NSAffineTransform()
    transform.translateX(by: CGFloat(size) * margin, yBy: CGFloat(size) * margin)
    transform.scale(by: CGFloat(size) * (1 - 2 * margin) / 256)
    transform.concat()
    rectangle(NSRect(x: 0, y: 0, width: 256, height: 256), radius: rounded ? 55 : 0, color: color(0x102E39))
    rectangle(NSRect(x: 117, y: 51, width: 81, height: 151), radius: 18, color: color(0x28777B))
    rectangle(NSRect(x: 58, y: 50, width: 37, height: 156), radius: 8, color: color(0xFFF6E5))
    rectangle(NSRect(x: 76, y: 172, width: 116, height: 34), radius: 8, color: color(0xFFF6E5))
    rectangle(NSRect(x: 76, y: 113, width: 86, height: 32), radius: 8, color: color(0xFFF6E5))
    guard let png = image.representation(using: .png, properties: [:]) else {
        preconditionFailure("The icon must encode as PNG.")
    }
    try png.write(to: url)
}

func writeContents(_ value: [String: Any], to directory: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try (data + Data("\n".utf8)).write(to: directory.appendingPathComponent("Contents.json"))
}

// MARK: - Actions - Asset Generation

for directory in [catalog, appIcon, preview] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}
let info: [String: Any] = ["author": "xcode", "version": 1]
try writeContents(["info": info], to: catalog)
try render(size: 1024, rounded: false, to: appIcon.appendingPathComponent("ios-1024.png"))
var images: [[String: String]] = [
    ["filename": "ios-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]
]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let filename = "mac-\(pixels).png"
        try render(size: pixels, rounded: true, margin: 0.08, to: appIcon.appendingPathComponent(filename))
        images.append(["filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
    }
}
try writeContents(["images": images, "info": info], to: appIcon)
try render(size: 256, rounded: true, to: preview.appendingPathComponent("icon.png"))
try writeContents(
    ["images": [["filename": "icon.png", "idiom": "universal"]], "info": info], to: preview)
print("Generated Fennavio app artwork.")
