// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import Observation

@Observable final class StatusPanelAnchor { var arrowX: CGFloat = 182.5 }

// The pointer and body share a single opaque surface.
struct StatusPanelShape: Shape {
    var arrowX: CGFloat
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 14, top: CGFloat = 10
        let x = min(max(arrowX, r + 12), rect.width - r - 12)
        var p = Path()
        p.move(to: CGPoint(x: r, y: top))
        p.addLine(to: CGPoint(x: x - 10, y: top))
        p.addLine(to: CGPoint(x: x, y: 0))
        p.addLine(to: CGPoint(x: x + 10, y: top))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: top))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: top + r), control: CGPoint(x: rect.maxX, y: top))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - r), control: CGPoint(x: 0, y: rect.maxY))
        p.addLine(to: CGPoint(x: 0, y: top + r))
        p.addQuadCurve(to: CGPoint(x: r, y: top), control: CGPoint(x: 0, y: top))
        p.closeSubpath()
        return p
    }
}

final class StatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}
