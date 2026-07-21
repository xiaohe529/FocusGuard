import AppKit
import Foundation

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // macOS Big Sur style rounded rect
    let r = size * 0.224
    let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)

    // Subtle warm gray gradient — quiet, professional
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            NSColor(white: 0.28, alpha: 1.0).cgColor,
            NSColor(white: 0.22, alpha: 1.0).cgColor,
        ] as CFArray,
        locations: [0, 1])!
    ctx.saveGState()
    path.addClip()
    ctx.drawLinearGradient(gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: [])
    ctx.restoreGState()

    // Thin inner border
    path.lineWidth = size * 0.008
    NSColor.white.withAlphaComponent(0.10).setStroke()
    path.stroke()

    // Small centered shield icon with comfortable negative space
    let symbolSize = size * 0.40
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .regular)
    let symbol = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let symbolRect = NSRect(
        x: (size - symbolSize) / 2,
        y: (size - symbolSize) / 2,
        width: symbolSize,
        height: symbolSize)
    NSColor.white.withAlphaComponent(0.88).set()
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