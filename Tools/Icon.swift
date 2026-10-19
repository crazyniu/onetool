// SPDX-License-Identifier: GPL-3.0-or-later
// Original 1Tool wrench artwork. ICNS packing adapted from reference MakeIcon.swift.
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset")
let resources = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Brand")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

// One open-jaw wrench with a punched handle; the same vector supplies every size.
func wrench(in rect: NSRect, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: .init(x: 36, y: 96))
    path.curve(to: .init(x: 37, y: 55), controlPoint1: .init(x: 20, y: 86), controlPoint2: .init(x: 21, y: 63))
    path.line(to: .init(x: 37, y: 16))
    path.curve(to: .init(x: 63, y: 16), controlPoint1: .init(x: 37, y: 0), controlPoint2: .init(x: 63, y: 0))
    path.line(to: .init(x: 63, y: 55))
    path.curve(to: .init(x: 64, y: 96), controlPoint1: .init(x: 79, y: 63), controlPoint2: .init(x: 80, y: 86))
    path.line(to: .init(x: 64, y: 75))
    path.line(to: .init(x: 50, y: 67))
    path.line(to: .init(x: 36, y: 75))
    path.close()
    path.appendOval(in: NSRect(x: 45, y: 12, width: 10, height: 10))
    path.windingRule = .evenOdd
    var transform = AffineTransform()
    transform.translate(x: rect.minX, y: rect.minY)
    transform.scale(x: rect.width / 100, y: rect.height / 100)
    path.transform(using: transform)
    color.setFill(); path.fill()
}
func png(width: Int, height: Int, draw: (NSRect) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
func appIcon(_ size: Int) -> Data {
    png(width: size, height: size) { rect in
        let tile = rect.insetBy(dx: rect.width * 0.07, dy: rect.height * 0.07)
        let shape = NSBezierPath(roundedRect: tile, xRadius: rect.width * 0.19, yRadius: rect.height * 0.19)
        NSGradient(starting: NSColor(calibratedRed: 0.12, green: 0.60, blue: 1, alpha: 1),
            ending: NSColor(calibratedRed: 0.015, green: 0.23, blue: 0.82, alpha: 1))!.draw(in: shape, angle: -90)
        NSColor.white.withAlphaComponent(0.35).setStroke()
        shape.lineWidth = max(0.6, rect.width * 0.002); shape.stroke()
        wrench(in: rect.insetBy(dx: rect.width * 0.225, dy: rect.height * 0.225), color: .white)
    }
}
let sizes: [(String, Int, String?)] = [
    ("icon_16x16",16,nil), ("icon_16x16@2x",32,"ic11"),
    ("icon_32x32",32,nil), ("icon_32x32@2x",64,"ic12"),
    ("icon_128x128",128,"ic07"), ("icon_128x128@2x",256,"ic13"),
    ("icon_256x256",256,"ic08"), ("icon_256x256@2x",512,"ic14"),
    ("icon_512x512",512,"ic09"), ("icon_512x512@2x",1024,"ic10")
]
func integer(_ value: Int) -> Data {
    var value = UInt32(value).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var entries = Data()
for (name, size, type) in sizes {
    let data = appIcon(size)
    try data.write(to: output.appendingPathComponent(name + ".png"))
    if let type { entries.append(Data(type.utf8)); entries.append(integer(8 + data.count)); entries.append(data) }
}
var icns = Data("icns".utf8); icns.append(integer(8 + entries.count)); icns.append(entries)
try icns.write(to: output.deletingLastPathComponent().appendingPathComponent("AppIcon.icns"))
try appIcon(1024).write(to: resources.appendingPathComponent("AppIcon-Default.png"))
let mark = png(width: 256, height: 256) { wrench(in: $0, color: .black) }
try mark.write(to: resources.appendingPathComponent("logo.png"))
let wordmark = png(width: 160, height: 256) { _ in
    wrench(in: NSRect(x: -48, y: 0, width: 256, height: 256), color: .black)
}
try wordmark.write(to: output.deletingLastPathComponent().appendingPathComponent("BrandMark.png"))
for scale in [1, 2] {
    let glyph = png(width: 26 * scale, height: 20 * scale) { rect in
        let side = CGFloat(18 * scale)
        wrench(in: NSRect(x: (rect.width - side) / 2, y: (rect.height - side) / 2, width: side, height: side), color: .black)
    }
    try glyph.write(to: output.deletingLastPathComponent().appendingPathComponent(scale == 1 ? "MenuBarIcon.png" : "MenuBarIcon@2x.png"))
}
print("Generated 1Tool wrench icons")
