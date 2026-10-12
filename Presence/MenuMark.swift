import AppKit

enum MenuMark {
    private static let idleImage = draw(recording: false, away: false)
    private static let recordingImage = draw(recording: true, away: false)
    private static let awayImage = draw(recording: false, away: true)
    private static let bothImage = draw(recording: true, away: true)

    static func image(recording: Bool, away: Bool) -> NSImage {
        switch (recording, away) {
        case (false, false): return idleImage
        case (true, false): return recordingImage
        case (false, true): return awayImage
        case (true, true): return bothImage
        }
    }

    private static func draw(recording: Bool, away: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let inset: CGFloat = 2.4
            let box = rect.insetBy(dx: inset, dy: inset)
            let center = NSPoint(x: box.midX, y: box.midY)
            let radius = min(box.width, box.height) / 2
            let path = NSBezierPath()
            path.appendArc(withCenter: center, radius: radius, startAngle: 115, endAngle: 65, clockwise: false)
            path.lineWidth = away ? 2.35 : 1.55
            path.lineCapStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            if recording {
                let dot = NSBezierPath(ovalIn: NSRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3))
                NSColor.black.setFill()
                dot.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
