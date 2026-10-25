#!/usr/bin/env swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - Types

struct AssetCatalogContents: Encodable {
    // MARK: - Types

    struct Info: Encodable {
        // MARK: - Variables

        let author = "xcode"
        let version = 1
    }

    struct Image: Encodable {
        // MARK: - Variables

        let filename: String
        let idiom: String
        let platform: String?
        let size: String?
        let scale: String?
    }

    // MARK: - Variables

    let info = Info()
    let images: [Image]?
}

// MARK: - Variables

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

func rectangle(_ bounds: CGRect, radius: CGFloat, color: NSColor, in context: CGContext) {
    context.setFillColor(color.cgColor)
    context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}

func render(size: Int, rounded: Bool, margin: CGFloat = 0, to url: URL) throws {
    guard
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: (rounded ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)
    else { preconditionFailure("The icon drawing context must be allocatable.") }
    context.translateBy(x: CGFloat(size) * margin, y: CGFloat(size) * margin)
    let scale = CGFloat(size) * (1 - 2 * margin) / 256
    context.scaleBy(x: scale, y: scale)
    rectangle(
        CGRect(x: 0, y: 0, width: 256, height: 256), radius: rounded ? 55 : 0, color: color(0x102E39), in: context)
    rectangle(CGRect(x: 117, y: 51, width: 81, height: 151), radius: 18, color: color(0x28777B), in: context)
    rectangle(CGRect(x: 58, y: 50, width: 37, height: 156), radius: 8, color: color(0xFFF6E5), in: context)
    rectangle(CGRect(x: 76, y: 172, width: 116, height: 34), radius: 8, color: color(0xFFF6E5), in: context)
    rectangle(CGRect(x: 76, y: 113, width: 86, height: 32), radius: 8, color: color(0xFFF6E5), in: context)
    guard let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { preconditionFailure("The icon must encode as PNG.") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        preconditionFailure("The icon PNG must be writable.")
    }
}

func writeContents(_ value: AssetCatalogContents, to directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    try (data + Data("\n".utf8)).write(to: directory.appendingPathComponent("Contents.json"))
}

// MARK: - Actions - Asset Generation

for directory in [catalog, appIcon, preview] {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}
try writeContents(AssetCatalogContents(images: nil), to: catalog)
try render(size: 1024, rounded: false, to: appIcon.appendingPathComponent("ios-1024.png"))
var images: [AssetCatalogContents.Image] = [
    .init(filename: "ios-1024.png", idiom: "universal", platform: "ios", size: "1024x1024", scale: nil)
]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let filename = "mac-\(pixels).png"
        try render(size: pixels, rounded: true, margin: 0.08, to: appIcon.appendingPathComponent(filename))
        images.append(
            .init(filename: filename, idiom: "mac", platform: nil, size: "\(size)x\(size)", scale: "\(scale)x"))
    }
}
try writeContents(AssetCatalogContents(images: images), to: appIcon)
try render(size: 256, rounded: true, to: preview.appendingPathComponent("icon.png"))
try writeContents(
    AssetCatalogContents(
        images: [.init(filename: "icon.png", idiom: "universal", platform: nil, size: nil, scale: nil)]),
    to: preview)
print("Generated Fennavio app artwork.")
