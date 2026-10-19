import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.04, green: 0.39, blue: 0.36, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 55, y: 55, width: 914, height: 914), xRadius: 212, yRadius: 212).fill()
        NSColor.white.withAlphaComponent(0.19).setFill()
        NSBezierPath(roundedRect: NSRect(x: 255, y: 233, width: 514, height: 558), xRadius: 150, yRadius: 150).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 448, y: 344, width: 124, height: 307), xRadius: 32, yRadius: 32).fill()
        NSBezierPath(ovalIn: NSRect(x: 462, y: 685, width: 96, height: 25)).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
