// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint; adapted for 1Tool.
import AppKit

// Curated for clear silhouettes at actual menu-bar size; the empty name is 1Tool's mark.
enum StatusIconSelection {
    static let gallery = [
        "", "gearshape.fill", "wrench.adjustable.fill", "hammer.fill", "screwdriver.fill", "paintbrush.pointed.fill", "puzzlepiece.fill", "shield.fill",
        "cube.fill", "shippingbox.fill", "square.stack.fill", "square.on.square.fill", "rectangle.stack.fill", "square.grid.2x2.fill", "circle.grid.2x2.fill", "square.grid.3x3.fill",
        "hexagon.fill", "diamond.fill", "seal.fill", "octagon.fill", "circle.lefthalf.filled", "square.lefthalf.filled", "triangle.lefthalf.filled", "pentagon.fill",
        "curlybraces", "command", "option", "shift.fill", "arrow.up.arrow.down", "arrow.left.arrow.right", "arrow.triangle.branch", "arrow.triangle.swap",
    ]
    static func sanitized(_ name: String?) -> String {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return gallery.contains(name) ? name : ""
    }
}

enum BrandGlyph {
    static let applicationIcon: NSImage = {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) } ?? NSImage()
    }()
    static let pointSize = NSSize(width: 22, height: 22)
    private static let symbolHeight: CGFloat = 18
    private static func base(in bundle: Bundle) -> NSImage? {
        let image = NSImage(size: pointSize)
        for resource in ["MenuBarIcon", "MenuBarIcon@2x"] {
            guard let url = bundle.url(forResource: resource, withExtension: "png"),
                  let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) else { continue }
            rep.size = pointSize
            image.addRepresentation(rep)
        }
        guard !image.representations.isEmpty else { return nil }
        image.isTemplate = true
        return image
    }
    static var chosenSymbolName: String {
        StatusIconSelection.sanitized(UserDefaults.standard.string(forKey: "appearance.icon"))
    }
    static func mark(symbolName: String = chosenSymbolName, bundle: Bundle = .main) -> NSImage? {
        customMark(named: StatusIconSelection.sanitized(symbolName)) ?? base(in: bundle)
    }

    /// A system symbol on the canvas the active symbols use, or nil when
    /// this Mac has no symbol by that name: a typo, or a name from a newer
    /// macOS that came with a settings backup.
    static func customMark(named name: String) -> NSImage? {
        guard !name.isEmpty else { return nil }
        return fixedSizeSymbol(named: name)
    }

    private static func fixedSizeSymbol(named name: String) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold)),
              symbol.size.width > 0,
              symbol.size.height > 0,
              let ink = inkBounds(of: symbol),
              ink.width > 0, ink.height > 0 else { return nil }
        let scale = min(symbolHeight / ink.height, (pointSize.width - 2) / ink.width)
        let drawSize = NSSize(width: symbol.size.width * scale,
                              height: symbol.size.height * scale)
        guard ink.width * scale >= 8, ink.height * scale >= 14 else { return nil }
        // Center visible ink rather than the symbol's padded box.
        let inkOrigin = NSPoint(x: ink.minX * scale, y: ink.minY * scale)
        let inkSize = NSSize(width: ink.width * scale, height: ink.height * scale)
        let image = NSImage(size: pointSize, flipped: false) { rect in
            let target = NSRect(x: rect.midX - inkOrigin.x - inkSize.width / 2,
                                y: rect.midY - inkOrigin.y - inkSize.height / 2,
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


    static func image(active: Bool, bundle: Bundle = .main) -> NSImage? {
        guard let source = mark(bundle: bundle) else { return nil }
        guard active else { return source }
        let image = NSImage(size: pointSize, flipped: false) { _ in
            let bounds = NSRect(origin: .zero, size: pointSize)
            source.draw(in: bounds)
            NSColor.systemGreen.setFill()
            bounds.fill(using: .sourceIn)
            return true
        }
        image.isTemplate = false
        return image
    }
}
