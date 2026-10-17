// Renders the RidePulse app icon (1024×1024 PNG) with Core Graphics.
// Usage: swift icon.swift <output.png> [variant]   variant: ios | watch
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "AppIcon.png"
let variant = args.count > 2 ? args[2] : "ios"
let S: CGFloat = 1024

let cs = CGColorSpaceCreateDeviceRGB()
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r/255, g/255, b/255, a])!
}

// Background: deep navy → teal diagonal gradient (iOS masks the corners itself;
// watchOS masks to a circle, so we fill the full square in both cases).
let bgColors = [rgb(12, 26, 54), rgb(10, 70, 110), rgb(16, 150, 120)] as CFArray
let bg = CGGradient(colorsSpace: cs, colors: bgColors, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

// Soft radial glow behind the mark.
let glow = CGGradient(colorsSpace: cs, colors: [rgb(60, 220, 160, 0.35), rgb(60, 220, 160, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S*0.5, y: S*0.5), startRadius: 0,
                       endCenter: CGPoint(x: S*0.5, y: S*0.5), endRadius: S*0.48, options: [])

let center = CGPoint(x: S/2, y: S/2)
let R: CGFloat = variant == "watch" ? 300 : 330   // wheel radius
let lw: CGFloat = 46                              // stroke weight

ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// Wheel: ring with a gap on the left/right where the pulse enters/exits.
ctx.setStrokeColor(rgb(255, 255, 255))
ctx.setLineWidth(lw)
let gap: CGFloat = 0.26 // radians half-gap
ctx.addArc(center: center, radius: R, startAngle: gap, endAngle: .pi - gap, clockwise: false)
ctx.strokePath()
ctx.addArc(center: center, radius: R, startAngle: .pi + gap, endAngle: 2 * .pi - gap, clockwise: false)
ctx.strokePath()

// Pulse line through the wheel: flat → spike → flat, in bright green with a shadow.
let y = center.y
let pulse = CGMutablePath()
pulse.move(to: CGPoint(x: 90, y: y))
pulse.addLine(to: CGPoint(x: 347, y: y))
pulse.addLine(to: CGPoint(x: 417, y: y + 60))
pulse.addLine(to: CGPoint(x: 487, y: y - 230))
pulse.addLine(to: CGPoint(x: 562, y: y + 260))
pulse.addLine(to: CGPoint(x: 627, y: y - 70))
pulse.addLine(to: CGPoint(x: 677, y: y))
pulse.addLine(to: CGPoint(x: S - 90, y: y))

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 30, color: rgb(0, 0, 0, 0.45))
ctx.setLineWidth(lw + 4)
ctx.setStrokeColor(rgb(12, 26, 54, 0.9))   // dark outline so the pulse pops over the white ring
ctx.addPath(pulse)
ctx.strokePath()
ctx.restoreGState()

ctx.setLineWidth(lw)
ctx.setStrokeColor(rgb(84, 240, 150))
ctx.addPath(pulse)
ctx.strokePath()

// Write PNG
let img = ctx.makeImage()!
let url = URL(fileURLWithPath: outPath) as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(outPath)")
