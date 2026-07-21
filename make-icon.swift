import AppKit
import Foundation

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let r = size * 0.224
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)

    // Solid warm yellow — no gradient
    NSColor(red: 0.92, green: 0.73, blue: 0.20, alpha: 1.0).setFill()
    path.fill()

    // Thin inner border
    path.lineWidth = size * 0.008
    NSColor.white.withAlphaComponent(0.15).setStroke()
    path.stroke()

    // Small centered shield — 30% of icon size
    let symbolSize = size * 0.30
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
    let symbol = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let symbolRect = NSRect(
        x: (size - symbolSize) / 2,
        y: (size - symbolSize) / 2 + size * 0.01,
        width: symbolSize,
        height: symbolSize)
    NSColor.white.withAlphaComponent(0.90).set()
    symbol.draw(in: symbolRect, from: NSRect(origin: .zero, size: symbol.size),
                operation: .sourceOver, fraction: 1.0)

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let fm = FileManager.default
let iconset = "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try? fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

for (name, px) in sizes {
    let img = renderIcon(size: px)
    savePNG(img, to: "\(iconset)/\(name).png")
}

print("Created \(iconset)")