import AppKit
import Foundation

// Render an SF Symbol to a single-color PNG at a given size.
func renderSymbol(name: String, size: CGFloat, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: .bold)
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
    let symbol = base.withSymbolConfiguration(config)!
    let target = NSImage(size: NSSize(width: size, height: size))
    target.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    color.set()
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    symbol.draw(in: rect, from: NSRect(origin: .zero, size: symbol.size), operation: .sourceOver, fraction: 1.0)
    ctx.fill(rect)
    target.unlockFocus()
    return target
}

// Save PNG to file
func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: path))
}

// Build a rounded-rect background with the lock.shield icon on top
func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    // Rounded rect background — gradient blue
    let path = NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22)
    NSColor(red: 0.18, green: 0.49, blue: 0.94, alpha: 1.0).setFill()
    path.fill()
    // White lock.shield icon centered
    let symbolSize = size * 0.7
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .bold)
    let symbol = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let symbolRect = NSRect(x: (size - symbolSize) / 2, y: (size - symbolSize) / 2, width: symbolSize, height: symbolSize)
    NSColor.white.set()
    symbol.draw(in: symbolRect, from: NSRect(origin: .zero, size: symbol.size), operation: .sourceOver, fraction: 1.0)
    image.unlockFocus()
    return image
}

// Build .iconset folder with standard sizes
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
