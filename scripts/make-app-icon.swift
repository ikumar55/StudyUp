// Renders the StudyUp app icon (light, dark, tinted) at 1024×1024.
// Same motif as web/client/public/icon.svg: two stacked cards with a rising line.
// Usage: swift scripts/make-app-icon.swift StudyUp/Assets.xcassets/AppIcon.appiconset
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let outDir = CommandLine.arguments[1]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

let cardW: CGFloat = 500, cardH: CGFloat = 580, radius: CGFloat = 104
let front = CGRect(x: 512 - cardW / 2 - 40, y: 512 - cardH / 2 + 30, width: cardW, height: cardH)
let backCenter = CGPoint(x: front.midX + 80, y: front.midY - 50)

// Line points as fractions of the front card (from the favicon: card 38×44, line 10,25 → 32,14).
let linePoints: [CGPoint] = [(10, 25), (18, 17), (24, 23), (32, 14)].map {
    CGPoint(x: front.minX + $0.0 / 38 * cardW, y: front.minY + $0.1 / 44 * cardH)
}

struct Style {
    var background: [CGColor]?   // gradient top → bottom, nil = transparent
    var backCard: CGColor
    var frontCard: CGColor
    var line: CGColor?           // nil = cut the line out of the front card
}

func render(_ style: Style, to name: String) {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        // The light icon must be opaque (no alpha channel).
                        bitmapInfo: (style.background == nil ? CGImageAlphaInfo.premultipliedLast
                                                             : CGImageAlphaInfo.noneSkipLast).rawValue)!
    // Flip so y grows downward, like the SVG.
    ctx.translateBy(x: 0, y: CGFloat(size))
    ctx.scaleBy(x: 1, y: -1)

    if let bg = style.background {
        let gradient = CGGradient(colorsSpace: nil, colors: bg as CFArray, locations: nil)!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size), options: [])
    }

    // Back card, rotated 10° about its own center.
    ctx.saveGState()
    ctx.translateBy(x: backCenter.x, y: backCenter.y)
    ctx.rotate(by: 10 * .pi / 180)
    ctx.addPath(CGPath(roundedRect: CGRect(x: -cardW / 2, y: -cardH / 2, width: cardW, height: cardH),
                       cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(style.backCard)
    ctx.fillPath()
    ctx.restoreGState()

    // Front card, with a soft shadow so it lifts off the back one.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 40, color: color(0x000000, 0.18))
    ctx.addPath(CGPath(roundedRect: front, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(style.frontCard)
    ctx.fillPath()
    ctx.restoreGState()

    // Rising line.
    ctx.addLines(between: linePoints)
    ctx.setLineWidth(72)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    if let line = style.line {
        ctx.setStrokeColor(line)
    } else {
        ctx.setBlendMode(.clear)
    }
    ctx.strokePath()

    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

// Light: blue background, white cards, blue line.
render(Style(background: [color(0x3d9bff), color(0x0062e0)],
             backCard: color(0xffffff, 0.45), frontCard: color(0xffffff), line: color(0x0a84ff)),
       to: "AppIcon.png")
// Dark: the system supplies a dark background; blue cards, white line (like the favicon).
render(Style(background: nil,
             backCard: color(0x8fb8ff, 0.7), frontCard: color(0x0a84ff), line: color(0xffffff)),
       to: "AppIcon-Dark.png")
// Tinted: grayscale on transparent; the system applies the tint.
render(Style(background: nil,
             backCard: color(0xffffff, 0.45), frontCard: color(0xffffff), line: nil),
       to: "AppIcon-Tinted.png")
