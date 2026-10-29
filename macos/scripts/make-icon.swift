// Draws Carrier's app icon and writes Resources/AppIcon.icns.
// Uses Resources/AppIcon-source.png if present; otherwise draws the default vector paper plane.
// Run from macos/:  swift scripts/make-icon.swift
import AppKit

let sourcePath = "Resources/AppIcon-source.png"
let sourceImage = NSImage(contentsOfFile: sourcePath)

func render(_ side: Int) -> Data {
    let size = CGFloat(side)
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        // the grid: the icon is 80% of the canvas, centred, with room for the shadow
        let body = rect.insetBy(dx: size * 0.1, dy: size * 0.1)
        let path = NSBezierPath(roundedRect: body, xRadius: body.width * 0.2237, yRadius: body.width * 0.2237)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
        shadow.shadowBlurRadius = size * 0.025
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.set()
        NSColor.black.setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        if let source = sourceImage {
            source.draw(in: body, from: NSRect(origin: .zero, size: source.size), operation: .copy, fraction: 1.0)
        } else {
            NSGradient(colors: [NSColor(red: 0.36, green: 0.55, blue: 1.0, alpha: 1), NSColor(red: 0.45, green: 0.30, blue: 0.95, alpha: 1)])!
                .draw(in: body, angle: -55)
            // a soft light from the top
            NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
                .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
            // the plane, white, a little to the upper right as paper planes fly
            let configuration = NSImage.SymbolConfiguration(pointSize: body.width * 0.46, weight: .semibold)
            if let symbol = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                let tinted = symbol.copy() as! NSImage
                tinted.lockFocus()
                NSColor.white.set()
                NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
                tinted.unlockFocus()
                let target = NSRect(x: body.midX - tinted.size.width / 2 + size * 0.01, y: body.midY - tinted.size.height / 2 - size * 0.005, width: tinted.size.width, height: tinted.size.height)
                tinted.draw(in: target)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return true
    }
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    bitmap.size = NSSize(width: side, height: side)
    return bitmap.representation(using: .png, properties: [:])!
}

let iconset = "Resources/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for (name, side) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(side).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(name).png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
try FileManager.default.removeItem(atPath: iconset)
print("wrote Resources/AppIcon.icns")
