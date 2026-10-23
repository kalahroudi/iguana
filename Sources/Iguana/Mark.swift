import AppKit

/// The iguana, as vector paths in a 1024-unit square (y down). Shared by the app icon and the menu bar glyph.
enum Mark {
    static let head: NSBezierPath = {
        let p = NSBezierPath()
        p.move(to: pt(236, 716))
        p.curve(to: pt(456, 410), controlPoint1: pt(150, 580), controlPoint2: pt(296, 430))
        p.curve(to: pt(790, 462), controlPoint1: pt(590, 394), controlPoint2: pt(706, 410))
        p.curve(to: pt(794, 616), controlPoint1: pt(856, 502), controlPoint2: pt(864, 580))
        p.curve(to: pt(574, 710), controlPoint1: pt(724, 652), controlPoint2: pt(650, 668))
        p.curve(to: pt(236, 716), controlPoint1: pt(470, 768), controlPoint2: pt(330, 810))
        p.close(); return p
    }()
    static let eyeRing = NSBezierPath(ovalIn: NSRect(x: 548, y: 452, width: 124, height: 124))
    static let crest: [NSBezierPath] = [
        [(300, 468), (262, 338), (372, 424)], [(388, 420), (368, 280), (470, 392)],
        [(480, 392), (478, 256), (568, 380)], [(572, 382), (596, 262), (660, 394)],
    ].map { t in let p = NSBezierPath(); p.move(to: pt(t[0].0, t[0].1)); p.line(to: pt(t[1].0, t[1].1)); p.line(to: pt(t[2].0, t[2].1)); p.close(); return p }
    static let dewlap: NSBezierPath = {
        let p = NSBezierPath()
        p.move(to: pt(446, 742))
        p.curve(to: pt(590, 800), controlPoint1: pt(470, 840), controlPoint2: pt(560, 872))
        p.curve(to: pt(510, 720), controlPoint1: pt(610, 756), controlPoint2: pt(560, 716))
        p.close(); return p
    }()
    static let scaleLine: NSBezierPath = {
        let p = NSBezierPath(); p.move(to: pt(300, 640))
        p.curve(to: pt(640, 572), controlPoint1: pt(420, 650), controlPoint2: pt(520, 620)); p.lineWidth = 14; p.lineCapStyle = .round; return p
    }()
    private static func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }
}

/// Monochrome menu bar glyph (template image: macOS tints it for light and dark bars).
enum StatusIcon {
    static func image() -> NSImage {
        let img = NSImage(size: NSSize(width: 21, height: 18), flipped: true) { rect in
            let s = rect.height / 630
            let t = NSAffineTransform(); t.scale(by: s); t.translateX(by: -150, yBy: -250)
            NSColor.black.setFill()
            for p in Mark.crest + [Mark.dewlap] { let c = p.copy() as! NSBezierPath; c.transform(using: t as AffineTransform); c.fill() }
            let h = NSBezierPath(); h.append(Mark.head); h.append(Mark.eyeRing); h.windingRule = .evenOdd
            h.transform(using: t as AffineTransform); h.fill()
            return true
        }
        img.isTemplate = true
        return img
    }
}

/// Full-colour app icon, drawn in code so the build needs no image tools.
enum AppIcon {
    static func image(size: CGFloat, padded: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let inset: CGFloat = padded ? 100 : 0
            let k = size / 1024 * (1024 - 2 * inset) / 896          // 896 = tile width in the 1024 design space
            let t = NSAffineTransform(); t.translateX(by: (inset * size / 1024) - 64 * k, yBy: (inset * size / 1024) - 64 * k); t.scale(by: k)
            func fill(_ p: NSBezierPath, _ c: NSColor) { let q = p.copy() as! NSBezierPath; q.transform(using: t as AffineTransform); c.setFill(); q.fill() }
            func rgb(_ h: UInt32, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a) }

            let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 204, yRadius: 204)
            let tt = tile.copy() as! NSBezierPath; tt.transform(using: t as AffineTransform)
            NSGradient(starting: rgb(0x1c6b4a), ending: rgb(0x06271d))?.draw(in: tt, angle: 60)
            NSGraphicsContext.saveGraphicsState(); tt.addClip()
            for y in [760, 836, 912] as [CGFloat] { fill(NSBezierPath(rect: NSRect(x: 64, y: y, width: 896, height: 44)), rgb(0xffffff, 0.07)) }
            NSGraphicsContext.restoreGraphicsState()

            for c in Mark.crest { fill(c, rgb(0x3fbf7a)) }
            let hd = Mark.head.copy() as! NSBezierPath; hd.transform(using: t as AffineTransform)
            NSGradient(starting: rgb(0xd9ff7a), ending: rgb(0x7fe08a))?.draw(in: hd, angle: 45)
            fill(Mark.dewlap, rgb(0xff9f43))
            let sl = Mark.scaleLine.copy() as! NSBezierPath; sl.transform(using: t as AffineTransform); sl.lineWidth = 14 * k
            rgb(0x2a8f5a, 0.55).setStroke(); sl.stroke()
            fill(NSBezierPath(ovalIn: NSRect(x: 548, y: 452, width: 124, height: 124)), rgb(0x0b3d2e))
            fill(NSBezierPath(ovalIn: NSRect(x: 556, y: 460, width: 108, height: 108)), rgb(0xfff3b0))
            fill(NSBezierPath(ovalIn: NSRect(x: 601, y: 474, width: 30, height: 80)), rgb(0x06271d))
            fill(NSBezierPath(ovalIn: NSRect(x: 617, y: 485, width: 18, height: 18)), .white)
            fill(NSBezierPath(ovalIn: NSRect(x: 787, y: 507, width: 26, height: 26)), rgb(0x0b3d2e, 0.8))
            return true
        }
    }

    static func writeIconset(to dir: String) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let sizes: [(String, CGFloat)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                                          ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
        for (name, px) in sizes {
            guard let tiff = image(size: px, padded: true).tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("icon_\(name).png"))
        }
    }
}
