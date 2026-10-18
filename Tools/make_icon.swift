import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the Duo Tanks app icon at 1024×1024. Usage: swift make_icon.swift <output.png>
let size = 1024.0
let space = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map(\.0) as CFArray, locations: stops.map(\.1))!
}

// Sky
ctx.drawLinearGradient(gradient([
    (color(0.04, 0.05, 0.17), 0), (color(0.16, 0.11, 0.36), 0.5), (color(0.62, 0.3, 0.45), 0.8), (color(0.98, 0.58, 0.42), 1),
]), start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size), options: [])

// Stars
var seed: UInt64 = 7
func random() -> Double {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return Double(seed >> 33) / Double(1 << 31)
}
for _ in 0..<70 {
    let x = random() * size, y = pow(random(), 1.5) * size * 0.5, r = 1.5 + random() * 3
    ctx.setFillColor(color(1, 1, 1, 0.4 + random() * 0.6))
    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
}

// Moon with glow
let moon = CGPoint(x: 760, y: 250)
ctx.drawRadialGradient(gradient([(color(1, 0.95, 0.8, 0.45), 0), (color(1, 0.9, 0.8, 0), 1)]),
                       startCenter: moon, startRadius: 70, endCenter: moon, endRadius: 280, options: [])
ctx.setFillColor(color(1, 0.97, 0.88))
ctx.fillEllipse(in: CGRect(x: moon.x - 88, y: moon.y - 88, width: 176, height: 176))
ctx.setFillColor(color(0.78, 0.74, 0.66, 0.5))
for (dx, dy, r) in [(-30.0, -20.0, 30.0), (28.0, 18.0, 22.0), (-8.0, 40.0, 16.0), (34.0, -34.0, 12.0)] {
    ctx.fillEllipse(in: CGRect(x: moon.x + dx - r, y: moon.y + dy - r, width: r * 2, height: r * 2))
}

// Hills: far ridge, near ridge, then the battlefield
func hill(_ base: Double, _ amplitude: Double, _ phase: Double, _ waves: Double, _ fill: CGColor) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: size))
    for x in stride(from: 0.0, through: size, by: 8) {
        let y = base - amplitude * (sin(x / size * .pi * waves + phase) * 0.6 + sin(x / size * .pi * waves * 2.3 + phase * 1.7) * 0.4)
        path.addLine(to: CGPoint(x: x, y: y))
    }
    path.addLine(to: CGPoint(x: size, y: size))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()
}
hill(600, 70, 0.6, 2.2, color(0.36, 0.26, 0.48))
hill(690, 60, 2.1, 2.8, color(0.21, 0.15, 0.32))

// Foreground ground with grass edge
let ground = CGMutablePath()
ground.move(to: CGPoint(x: 0, y: size))
var surface: [CGPoint] = []
for x in stride(from: 0.0, through: size, by: 6) {
    let y = 770 - 120 * exp(-pow((x - 260) / 190, 2)) - 40 * exp(-pow((x - 850) / 160, 2))
    surface.append(CGPoint(x: x, y: y))
}
ground.addLines(between: [CGPoint(x: 0, y: size)] + surface + [CGPoint(x: size, y: size)])
ground.closeSubpath()
ctx.saveGState()
ctx.addPath(ground)
ctx.clip()
ctx.drawLinearGradient(gradient([(color(0.5, 0.34, 0.19), 0), (color(0.22, 0.14, 0.09), 1)]),
                       start: CGPoint(x: 0, y: 640), end: CGPoint(x: 0, y: size), options: [])
ctx.restoreGState()
let rim = CGMutablePath()
rim.addLines(between: surface)
ctx.addPath(rim)
ctx.setStrokeColor(color(0.42, 0.78, 0.32))
ctx.setLineWidth(14)
ctx.setLineCap(.round)
ctx.strokePath()

// Shell arc from the tank to the far hill
// The barrel pivots 58 above the hull base at (262, 652), tilted 0.22π, and is 134 long.
let barrelAngle = Double.pi * 0.22
let muzzle = CGPoint(x: 262 + cos(barrelAngle) * 134, y: 652 - 58 - sin(barrelAngle) * 134)
let landing = CGPoint(x: 845, y: 715)
let control = CGPoint(x: 600, y: 170)
let arc = CGMutablePath()
arc.move(to: muzzle)
arc.addQuadCurve(to: landing, control: control)
ctx.saveGState()
ctx.addPath(arc)
ctx.setStrokeColor(color(1, 0.9, 0.7, 0.75))
ctx.setLineWidth(9)
ctx.setLineDash(phase: 0, lengths: [26, 20])
ctx.strokePath()
ctx.restoreGState()

// Explosion at the landing point
ctx.drawRadialGradient(gradient([
    (color(1, 1, 0.92, 1), 0), (color(1, 0.85, 0.3, 1), 0.25), (color(1, 0.45, 0.1, 0.85), 0.55), (color(0.9, 0.15, 0.05, 0), 1),
]), startCenter: landing, startRadius: 0, endCenter: landing, endRadius: 165, options: [])
for i in 0..<12 {
    let angle = Double(i) / 12 * .pi * 2 + 0.2
    let length = 120 + random() * 70
    let spark = CGMutablePath()
    spark.move(to: CGPoint(x: landing.x + cos(angle) * 60, y: landing.y + sin(angle) * 60))
    spark.addLine(to: CGPoint(x: landing.x + cos(angle) * length, y: landing.y + sin(angle) * length))
    ctx.addPath(spark)
    ctx.setStrokeColor(color(1, 0.8, 0.35, 0.9))
    ctx.setLineWidth(7)
    ctx.strokePath()
}

// Glowing shell near the top of its arc
// A point partway along the quadratic arc.
let t = 0.42
let shell = CGPoint(x: (1 - t) * (1 - t) * muzzle.x + 2 * t * (1 - t) * control.x + t * t * landing.x,
                    y: (1 - t) * (1 - t) * muzzle.y + 2 * t * (1 - t) * control.y + t * t * landing.y)
ctx.drawRadialGradient(gradient([(color(1, 0.75, 0.3, 0.95), 0), (color(1, 0.4, 0.1, 0), 1)]),
                       startCenter: shell, startRadius: 0, endCenter: shell, endRadius: 46, options: [])
ctx.setFillColor(color(1, 1, 0.95))
ctx.fillEllipse(in: CGRect(x: shell.x - 13, y: shell.y - 13, width: 26, height: 26))

// The tank on the hilltop, barrel raised toward the arc
let base = CGPoint(x: 262, y: 652)
let red = color(0.86, 0.22, 0.18), redDark = color(0.5, 0.1, 0.08), steel = color(0.14, 0.14, 0.16)
ctx.saveGState()
ctx.translateBy(x: base.x, y: base.y)
// barrel
ctx.saveGState()
ctx.translateBy(x: 0, y: -58)
ctx.rotate(by: -.pi * 0.22)
ctx.setFillColor(redDark)
ctx.fill(CGRect(x: 0, y: -11, width: 128, height: 22))
ctx.fill(CGRect(x: 108, y: -16, width: 26, height: 32))
ctx.restoreGState()
// turret
ctx.setFillColor(red)
let dome = CGPath(roundedRect: CGRect(x: -58, y: -96, width: 116, height: 64), cornerWidth: 32, cornerHeight: 32, transform: nil)
ctx.addPath(dome)
ctx.fillPath()
// hull
let hull = CGMutablePath()
hull.addLines(between: [CGPoint(x: -122, y: -14), CGPoint(x: -100, y: -56), CGPoint(x: 92, y: -56), CGPoint(x: 126, y: -18), CGPoint(x: 122, y: -14)])
hull.closeSubpath()
ctx.addPath(hull)
ctx.setFillColor(red)
ctx.fillPath()
ctx.setFillColor(color(1, 1, 1, 0.3))
ctx.fill(CGRect(x: -98, y: -58, width: 186, height: 7))
// tracks and wheels
let track = CGPath(roundedRect: CGRect(x: -132, y: -26, width: 264, height: 46), cornerWidth: 23, cornerHeight: 23, transform: nil)
ctx.addPath(track)
ctx.setFillColor(steel)
ctx.fillPath()
for i in 0..<6 {
    let x = -105 + Double(i) * 42
    ctx.setFillColor(color(0.55, 0.55, 0.58))
    ctx.fillEllipse(in: CGRect(x: x - 15, y: -18, width: 30, height: 30))
    ctx.setFillColor(color(0.3, 0.3, 0.33))
    ctx.fillEllipse(in: CGRect(x: x - 6, y: -9, width: 12, height: 12))
}
ctx.restoreGState()

// Muzzle flash
ctx.drawRadialGradient(gradient([(color(1, 0.95, 0.7, 0.95), 0), (color(1, 0.5, 0.1, 0), 1)]),
                       startCenter: muzzle, startRadius: 0, endCenter: muzzle, endRadius: 60, options: [])

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("wrote \(output.path)")
