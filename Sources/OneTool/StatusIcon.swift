// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint; adapted for 1Tool.
import AppKit

// Same empty-name default, gallery, and invalid-name recovery as the reference project.
enum StatusIconSelection {
    static func sanitized(_ name: String?) -> String { name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
    static func toSave(typed: String?, opening: String, exists: (String) -> Bool) -> String {
        let name = sanitized(typed)
        return name.isEmpty || exists(name) ? name : opening
    }
    static let gallery = [
        "bolt.fill", "star.fill", "heart.fill", "flame.fill", "sparkles", "leaf.fill",
        "drop.fill", "snowflake", "sun.max.fill", "moon.stars.fill", "cloud.fill", "mountain.2.fill",
        "circle.fill", "square.fill", "triangle.fill", "diamond.fill", "hexagon.fill", "seal.fill",
        "circle.lefthalf.filled", "circle.hexagongrid.fill", "infinity",
        "command", "cpu.fill", "memorychip.fill", "gauge.with.dots.needle.67percent",
        "fanblades.fill", "gearshape.fill", "terminal.fill", "waveform",
        "wand.and.stars", "key.fill", "crown.fill", "gamecontroller.fill", "headphones",
        "music.note", "paperplane.fill", "pawprint.fill", "cat.fill", "hare.fill", "tortoise.fill",
    ]

}

enum BrandGlyph {
    static let applicationIcon: NSImage = {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) } ?? NSImage()
    }()
    static let pointSize = NSSize(width: 26, height: 20)
    private static let symbolHeight: CGFloat = 16
    private static let base: NSImage? = {
        let image = NSImage(size: pointSize)
        for resource in ["MenuBarIcon", "MenuBarIcon@2x"] {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let rep = NSBitmapImageRep(data: data)
            else { continue }
            rep.size = pointSize
            image.addRepresentation(rep)
        }
        guard !image.representations.isEmpty else { return nil }
        image.isTemplate = true
        return image
    }()

    /// The symbol named in the menu bar settings, empty for the mark.
    static var chosenSymbolName: String {
        StatusIconSelection.sanitized(UserDefaults.standard.string(forKey: "appearance.icon"))
    }

    /// What every state starts from: the chosen symbol, or the bundled mark
    /// when none is chosen or this Mac has no symbol by that name.
    static func mark(symbolName: String = BrandGlyph.chosenSymbolName) -> NSImage? {
        customMark(named: symbolName) ?? base
    }

    /// A system symbol on the canvas the active symbols use, or nil when
    /// this Mac has no symbol by that name: a typo, or a name from a newer
    /// macOS that came with a settings backup.
    static func customMark(named name: String) -> NSImage? {
        guard !name.isEmpty else { return nil }
        return fixedSizeSymbol(named: name)
    }

    private static func fixedSizeSymbol(named name: String, drop: CGFloat = 0) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold)),
              symbol.size.width > 0,
              symbol.size.height > 0,
              let ink = inkBounds(of: symbol),
              ink.width > 0, ink.height > 0 else { return nil }
        let scale = min(symbolHeight / ink.height, (pointSize.width - 2) / ink.width)
        let drawSize = NSSize(width: symbol.size.width * scale,
                              height: symbol.size.height * scale)
        // Offsets used to center the ink rather than the padded box.
        let inkOrigin = NSPoint(x: ink.minX * scale, y: ink.minY * scale)
        let inkSize = NSSize(width: ink.width * scale, height: ink.height * scale)
        let image = NSImage(size: pointSize, flipped: false) { rect in
            let target = NSRect(x: rect.midX - inkOrigin.x - inkSize.width / 2,
                                y: rect.midY - inkOrigin.y - inkSize.height / 2 - drop,
                                width: drawSize.width,
                                height: drawSize.height)
            symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Bounding box of an image's visible pixels, in its own (bottom-up) point
    /// space. Only runs when the menu bar icon changes, so rasterizing is cheap.
    private static func inkBounds(of image: NSImage) -> NSRect? {
        let sampling = 2
        let wide = Int(ceil(image.size.width)) * sampling
        let high = Int(ceil(image.size.height)) * sampling
        guard wide > 0, high > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: wide, pixelsHigh: high,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // The context comes from the rep's pixel dimensions, so it draws in
        // pixels; fill the whole bitmap and scale the bounds back down. A
        // point-sized rect here would only cover a corner of it.
        image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(wide), height: CGFloat(high)))
        NSGraphicsContext.restoreGraphicsState()

        var minX = wide, minY = high, maxX = -1, maxY = -1
        for y in 0..<high {
            for x in 0..<wide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // colorAt() reads top-down; NSImage coordinates run bottom-up.
        let unit = CGFloat(sampling)
        return NSRect(x: CGFloat(minX) / unit,
                      y: CGFloat(high - 1 - maxY) / unit,
                      width: CGFloat(maxX - minX + 1) / unit,
                      height: CGFloat(maxY - minY + 1) / unit)
    }


    static func image(active: Bool, showDot: Bool) -> NSImage? {
        guard let source = mark()?.copy() as? NSImage else { return nil }
        guard active && showDot else { source.isTemplate = true; return source }
        let image = NSImage(size: NSSize(width: pointSize.width + 6, height: pointSize.height), flipped: false) { _ in
            source.draw(in: NSRect(origin: .zero, size: pointSize))
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: pointSize.width + 1, y: 8, width: 4, height: 4)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
