import AppKit

// Draws the app icon: dark rounded square, amber amp-style knob, waveform arc.
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: artwork inset ~10%
    let inset = s * 0.1
    let rect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    ctx.saveGState(); bg.addClip()
    NSGradient(colors: [NSColor(red: 0.98, green: 0.62, blue: 0.22, alpha: 1),
                        NSColor(red: 0.74, green: 0.30, blue: 0.10, alpha: 1)])!
        .draw(in: rect, angle: -90)
    ctx.restoreGState()

    let butter = NSColor(red: 1.0, green: 0.84, blue: 0.32, alpha: 1)
    let butterDark = NSColor(red: 0.93, green: 0.66, blue: 0.14, alpha: 1)
    let ink = NSColor(red: 0.30, green: 0.18, blue: 0.06, alpha: 1)

    // Guitar drawn in unit coordinates (1 = icon width), tilted 40 degrees.
    ctx.saveGState()
    ctx.translateBy(x: s * 0.5, y: s * 0.5)
    ctx.rotate(by: .pi * 40 / 180)
    ctx.scaleBy(x: s * 0.80, y: s * 0.80)
    ctx.translateBy(x: 0, y: -0.11)

    func oval(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
    }
    // One merged silhouette so no internal outlines show.
    var parts: [CGPath] = [
        CGPath(ellipseIn: CGRect(x: -0.215, y: -0.35, width: 0.43, height: 0.40), transform: nil),
        CGPath(ellipseIn: CGRect(x: -0.16, y: -0.10, width: 0.32, height: 0.28), transform: nil),
        CGPath(rect: CGRect(x: -0.115, y: -0.06, width: 0.23, height: 0.16), transform: nil),
        CGPath(roundedRect: CGRect(x: -0.032, y: 0.10, width: 0.064, height: 0.38), cornerWidth: 0.012, cornerHeight: 0.012, transform: nil),
        CGPath(roundedRect: CGRect(x: -0.05, y: 0.46, width: 0.10, height: 0.11), cornerWidth: 0.025, cornerHeight: 0.025, transform: nil),
    ]
    var merged = parts.removeFirst()
    for part in parts { merged = merged.union(part, using: .winding) }
    let shape = NSBezierPath(cgPath: merged)

    ctx.setShadow(offset: CGSize(width: 0.0, height: -0.012), blur: 0.03, color: NSColor(white: 0, alpha: 0.5).cgColor)
    butterDark.setFill(); shape.fill()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    NSGradient(colors: [butter, NSColor(red: 1.0, green: 0.93, blue: 0.55, alpha: 1), butter])!.draw(in: shape, angle: 35)
    shape.lineWidth = 0.009; ink.withAlphaComponent(0.6).setStroke(); shape.stroke()

    // sound hole, bridge, strings, tuning pegs
    ink.setFill(); oval(0, -0.04, 0.062, 0.062).fill()
    NSBezierPath(roundedRect: CGRect(x: -0.07, y: -0.285, width: 0.14, height: 0.022), xRadius: 0.008, yRadius: 0.008).fill()
    for dx in [-0.014, -0.005, 0.005, 0.014] as [CGFloat] {
        let st = NSBezierPath(); st.move(to: CGPoint(x: dx * 0.9, y: -0.275)); st.line(to: CGPoint(x: dx * 0.9, y: 0.54))
        st.lineWidth = 0.003; ink.withAlphaComponent(0.7).setStroke(); st.stroke()
    }
    for (x, y) in [(-0.06, 0.50), (-0.06, 0.54), (0.06, 0.50), (0.06, 0.54)] as [(CGFloat, CGFloat)] {
        ink.setFill(); oval(x, y, 0.011, 0.011).fill()
    }

    // glossy highlight
    let shine = NSBezierPath()
    shine.appendArc(withCenter: CGPoint(x: 0, y: -0.15), radius: 0.17, startAngle: 135, endAngle: 175, clockwise: false)
    shine.lineWidth = 0.014; shine.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.75).setStroke(); shine.stroke()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = CommandLine.arguments[1]
let sizes: [(String, Int)] = [("16",16),("16@2x",32),("32",32),("32@2x",64),("128",128),("128@2x",256),
                              ("256",256),("256@2x",512),("512",512),("512@2x",1024)]
for (name, px) in sizes {
    try! render(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name.replacingOccurrences(of: "@2x", with: ""))x\(name.replacingOccurrences(of: "@2x", with: ""))\(name.contains("@2x") ? "@2x" : "").png"))
}
