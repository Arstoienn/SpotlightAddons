import AppKit

// Draws Spotlight Add-ons's icon, a magnifying glass with a plus in it, black on white, into
// AppIcon.icns beside this file:
//     swift icon.swift
// The result is kept in the repository, so this is only run again to change the icon. The entry
// for the clipboard history is drawn the same way, by the app itself (Sources/Commands.swift).

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let iconset = here.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func png(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    // The rounded square of a macOS icon, with the margin the system's own icons leave round it:
    // white, with a hairline so that it has an edge on a white ground.
    let tile = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.1, dy: size * 0.1)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(starting: .white, ending: NSColor(white: 0.93, alpha: 1))!.draw(in: shape, angle: -90)
    NSColor(white: 0, alpha: 0.16).setStroke()
    shape.lineWidth = max(1, size / 256)
    shape.stroke()
    let symbol = NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: tile.width * 0.5, weight: .medium).applying(.init(paletteColors: [NSColor(white: 0.08, alpha: 1)])))!
    let fit = min(tile.width * 0.6 / symbol.size.width, tile.height * 0.6 / symbol.size.height)
    let drawn = NSSize(width: symbol.size.width * fit, height: symbol.size.height * fit)
    symbol.draw(in: NSRect(x: tile.midX - drawn.width / 2, y: tile.midY - drawn.height / 2, width: drawn.width, height: drawn.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try png(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let make = Process()
make.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
make.arguments = ["-c", "icns", iconset.path, "-o", here.appendingPathComponent("AppIcon.icns").path]
try make.run()
make.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(make.terminationStatus == 0 ? "wrote AppIcon.icns" : "iconutil failed")
