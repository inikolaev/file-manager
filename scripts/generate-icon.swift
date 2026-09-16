import AppKit

// Editable vector artwork, rendered directly at each macOS icon resolution.
// Keep small variants simpler rather than shrinking detailed artwork blindly.
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets")
let iconset = output.appendingPathComponent("Commander.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func render(pixels: Int, small: Bool) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }
    let body = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 196, yRadius: 196)
    if !small {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color(0.01, 0.02, 0.10, 0.35)
        shadow.shadowBlurRadius = 24
        shadow.shadowOffset = NSSize(width: 0, height: -12)
        shadow.set()
        color(0.03, 0.07, 0.22).setFill()
        body.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGradient(starting: color(0.08, 0.20, 0.57), ending: color(0.02, 0.05, 0.23))!.draw(in: body, angle: -90)
    if !small {
        color(0.45, 0.70, 1, 0.25).setStroke()
        body.lineWidth = 3
        body.stroke()
    }
    let cyan = color(0.15, 0.88, 0.94)
    let softCyan = color(0.31, 0.69, 0.86)
    let yellow = color(1, 0.86, 0.27)
    for (index, x) in [CGFloat(174), 536].enumerated() {
        let panel = NSBezierPath(roundedRect: NSRect(x: x, y: 228, width: 314, height: 568), xRadius: 24, yRadius: 24)
        color(0.015, 0.045, 0.23, 0.65).setFill()
        panel.fill()
        (index == 0 ? cyan : softCyan).setStroke()
        panel.lineWidth = small ? 24 : 14
        panel.stroke()
        // Header rule and file rows read as twin file panels even at Dock sizes.
        rounded(NSRect(x: x + 30, y: 699, width: 254, height: small ? 22 : 12), radius: 6, fill: index == 0 ? cyan : softCyan)
        if index == 0 {
            rounded(NSRect(x: x + 30, y: 577, width: 254, height: 76), radius: small ? 4 : 10, fill: yellow)
            if !small {
                let arrow = NSBezierPath()
                arrow.move(to: NSPoint(x: x + 57, y: 594))
                arrow.line(to: NSPoint(x: x + 78, y: 615))
                arrow.line(to: NSPoint(x: x + 57, y: 636))
                arrow.lineWidth = 9
                arrow.lineJoinStyle = .round
                color(0.05, 0.10, 0.25).setStroke()
                arrow.stroke()
                rounded(NSRect(x: x + 104, y: 607, width: 142, height: 16), radius: 4, fill: color(0.05, 0.10, 0.25))
            }
        } else {
            rounded(NSRect(x: x + 38, y: 602, width: 202, height: small ? 30 : 23), radius: 6, fill: softCyan)
        }
        for (row, width) in [CGFloat(216), 160, 190].enumerated() {
            if small && row == 2 { continue }
            rounded(NSRect(x: x + 38, y: 507 - CGFloat(row) * 94, width: width, height: small ? 30 : 23), radius: 6,
                    fill: index == 0 ? cyan : softCyan)
        }
    }
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale, small: points <= 32).write(to: iconset.appendingPathComponent(name))
    }
}
print("Generated \(iconset.path)")
