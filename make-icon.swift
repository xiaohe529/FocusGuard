import AppKit
import Foundation

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // Badge: smaller rounded rectangle, inset ~14% from each edge
    let inset = size * 0.14
    let badgeRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let badgeR = badgeRect.width * 0.224
    let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeR, yRadius: badgeR)

    // Subtle drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: size * 0.04),
                  blur: size * 0.08,
                  color: NSColor.black.withAlphaComponent(0.25).cgColor)
    NSColor(red: 0.18, green: 0.35, blue: 0.62, alpha: 1.0).setFill()
    badgePath.fill()
    ctx.restoreGState()

    // Gradient overlay on badge
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [
            NSColor(red: 0.20, green: 0.38, blue: 0.65, alpha: 1.0).cgColor,
            NSColor(red: 0.16, green: 0.32, blue: 0.58, alpha: 1.0).cgColor,
        ] as CFArray,
        locations: [0, 1])!
    ctx.saveGState()
    badgePath.addClip()
    ctx.drawLinearGradient(gradient,
        start: CGPoint(x: 0, y: size),
        end: CGPoint(x: size, y: 0),
        options: [])
    ctx.restoreGState()

    // Inner highlight
    let hl = NSBezierPath(roundedRect: badgeRect.insetBy(dx: badgeRect.width * 0.02, dy: badgeRect.height * 0.02),
                           xRadius: badgeR * 0.85, yRadius: badgeR * 0.85)
    hl.lineWidth = size * 0.005
    NSColor.white.withAlphaComponent(0.10).setStroke()
    hl.stroke()

    // Small shield symbol inside badge
    let symbolSize = badgeRect.width * 0.28
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
    let symbol = NSImage(systemSymbolName: "lock.shield.fill", accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let symbolRect = NSRect(
        x: (size - symbolSize) / 2,
        y: (size - symbolSize) / 2 - size * 0.005,
        width: symbolSize,
        height: symbolSize)
    NSColor.white.withAlphaComponent(0.92).set()
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