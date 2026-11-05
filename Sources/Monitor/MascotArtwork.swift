import AppKit

enum MascotFrame: String, CaseIterable {
    case awake, focus, blink, sleeping, waiting
}

/// The small-size companion to the illustrated A logo. Shared by the app and asset exporter.
enum MascotArtwork {
    static func image(frame: MascotFrame = .awake, size: CGFloat = 128, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            c.saveGState()
            defer { c.restoreGState() }
            c.scaleBy(x: size / 128, y: size / 128)
            draw(in: c, frame: frame, template: template)
            return true
        }
        image.isTemplate = template
        image.accessibilityDescription = "镜头发夹机娘"
        return image
    }

    private static func draw(in c: CGContext, frame: MascotFrame, template: Bool) {
        let ink = NSColor(srgbRed: 0.08, green: 0.20, blue: 0.14, alpha: 1).cgColor
        let hair = NSColor(srgbRed: 0.20, green: 0.35, blue: 0.26, alpha: 1).cgColor
        let cream = NSColor(srgbRed: 1, green: 0.94, blue: 0.83, alpha: 1).cgColor
        let peach = NSColor(srgbRed: 1, green: 0.87, blue: 0.74, alpha: 1).cgColor
        let orange = NSColor(srgbRed: 0.94, green: 0.57, blue: 0.27, alpha: 1).cgColor
        let black = NSColor.black.cgColor
        c.setLineCap(.round)
        c.setLineJoin(.round)

        func fill(_ path: CGPath, _ color: CGColor, outline: CGFloat = 0, cutout: Bool = false) {
            c.saveGState()
            if template && cutout { c.setBlendMode(.clear) }
            c.addPath(path)
            c.setFillColor(template ? black : color)
            c.fillPath()
            c.restoreGState()
            if outline > 0 && !template {
                c.addPath(path); c.setStrokeColor(ink); c.setLineWidth(outline); c.strokePath()
            }
        }
        func oval(_ rect: CGRect, _ color: CGColor, cutout: Bool = false) {
            fill(CGPath(ellipseIn: rect, transform: nil), color, cutout: cutout)
        }
        func line(_ points: [CGPoint], width: CGFloat = 3, color: CGColor? = nil) {
            c.beginPath(); c.move(to: points[0])
            for point in points.dropFirst() { c.addLine(to: point) }
            c.setStrokeColor(template ? black : (color ?? ink)); c.setLineWidth(width); c.strokePath()
        }
        func curve(_ start: CGPoint, _ end: CGPoint, _ a: CGPoint, _ b: CGPoint, width: CGFloat = 3) {
            c.beginPath(); c.move(to: start); c.addCurve(to: end, control1: a, control2: b)
            c.setStrokeColor(template ? black : ink); c.setLineWidth(width); c.strokePath()
        }

        // Broad bob silhouette and oversized lens remain legible at 16–18 points.
        let bob = CGMutablePath()
        bob.move(to: CGPoint(x: 13, y: 107))
        bob.addCurve(to: CGPoint(x: 14, y: 46), control1: CGPoint(x: 4, y: 91), control2: CGPoint(x: 8, y: 63))
        bob.addCurve(to: CGPoint(x: 65, y: 12), control1: CGPoint(x: 19, y: 19), control2: CGPoint(x: 40, y: 10))
        bob.addCurve(to: CGPoint(x: 115, y: 54), control1: CGPoint(x: 96, y: 10), control2: CGPoint(x: 112, y: 27))
        bob.addCurve(to: CGPoint(x: 115, y: 108), control1: CGPoint(x: 122, y: 81), control2: CGPoint(x: 122, y: 95))
        bob.addLine(to: CGPoint(x: 98, y: 104)); bob.addLine(to: CGPoint(x: 95, y: 117))
        bob.addCurve(to: CGPoint(x: 30, y: 117), control1: CGPoint(x: 70, y: 124), control2: CGPoint(x: 47, y: 123))
        bob.addLine(to: CGPoint(x: 26, y: 104)); bob.closeSubpath()
        fill(bob, hair, outline: 4)
        let face = CGPath(roundedRect: CGRect(x: 25, y: 36, width: 76, height: 77), cornerWidth: 35, cornerHeight: 32, transform: nil)
        fill(face, peach, cutout: true)
        let fringe = CGMutablePath()
        fringe.move(to: CGPoint(x: 22, y: 72)); fringe.addLine(to: CGPoint(x: 21, y: 37))
        fringe.addCurve(to: CGPoint(x: 99, y: 35), control1: CGPoint(x: 34, y: 15), control2: CGPoint(x: 78, y: 18))
        fringe.addLine(to: CGPoint(x: 105, y: 71))
        fringe.addCurve(to: CGPoint(x: 67, y: 46), control1: CGPoint(x: 89, y: 68), control2: CGPoint(x: 74, y: 56))
        fringe.addLine(to: CGPoint(x: 77, y: 71))
        fringe.addCurve(to: CGPoint(x: 47, y: 48), control1: CGPoint(x: 58, y: 72), control2: CGPoint(x: 52, y: 60))
        fringe.addCurve(to: CGPoint(x: 22, y: 72), control1: CGPoint(x: 41, y: 64), control2: CGPoint(x: 31, y: 69))
        fringe.closeSubpath(); fill(fringe, hair)
        if !template {
            curve(CGPoint(x: 23, y: 43), CGPoint(x: 51, y: 25), CGPoint(x: 29, y: 31), CGPoint(x: 39, y: 26), width: 3)
            for x: CGFloat in [17, 101] {
                fill(CGPath(roundedRect: CGRect(x: x, y: 73, width: 10, height: 24), cornerWidth: 5, cornerHeight: 5, transform: nil), cream, outline: 2)
            }
        }

        let closed = frame == .blink || frame == .sleeping
        for x: CGFloat in [43, 79] {
            if closed {
                curve(CGPoint(x: x - 6, y: 83), CGPoint(x: x + 6, y: 83), CGPoint(x: x - 2, y: 87), CGPoint(x: x + 2, y: 87), width: template ? 4 : 3)
            } else {
                oval(CGRect(x: x - 4, y: 75, width: 8, height: frame == .focus ? 9 : 13), ink)
                if !template { oval(CGRect(x: x - 2, y: 76, width: 3, height: 4), cream) }
            }
        }
        if frame == .waiting {
            line([CGPoint(x: 37, y: 70), CGPoint(x: 48, y: 67)], width: 3)
            oval(CGRect(x: 59, y: 96, width: 6, height: 6), ink)
        } else {
            curve(CGPoint(x: 56, y: 98), CGPoint(x: 68, y: 98), CGPoint(x: 59, y: 103), CGPoint(x: 65, y: 103), width: template ? 3 : 2.5)
        }
        if !template {
            oval(CGRect(x: 29, y: 91, width: 12, height: 5), orange)
            oval(CGRect(x: 84, y: 91, width: 12, height: 5), orange)
        }

        // The circular camera hair clip is the A concept's identifying feature.
        oval(CGRect(x: 74, y: 10, width: 45, height: 45), ink)
        oval(CGRect(x: 78, y: 14, width: 37, height: 37), cream, cutout: true)
        oval(CGRect(x: 83, y: 19, width: 27, height: 27), ink)
        let inset: CGFloat = frame == .focus || frame == .blink ? 3 : 0
        if template {
            oval(CGRect(x: 88 + inset / 2, y: 24 + inset / 2, width: 17 - inset, height: 17 - inset), cream, cutout: true)
        } else {
            oval(CGRect(x: 87 + inset / 2, y: 23 + inset / 2, width: 19 - inset, height: 19 - inset), orange)
            oval(CGRect(x: 89, y: 25, width: 7, height: 5), cream)
        }
    }
}
