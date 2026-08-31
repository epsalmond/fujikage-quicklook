#!/usr/bin/env swift
import AppKit

let canvas: CGFloat = 1024
let inset: CGFloat = 118
let card = CGRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let cardRadius = card.width * 0.21

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawPNG(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
    ctx.restoreGState()
}

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let fujiURL = [scriptDir, cwd.appendingPathComponent("scripts"), cwd]
    .map { $0.appendingPathComponent("fuji-1024.png") }
    .first { FileManager.default.isReadableFile(atPath: $0.path) }
guard let fujiURL,
      let fujiNS = NSImage(contentsOf: fujiURL),
      let fuji = fujiNS.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    fputs("missing fuji-1024.png\n", stderr)
    exit(1)
}

let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: true) { _ in
    guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 36, color: color(0, 0, 0, 0.45))
    ctx.setFillColor(color(0.008, 0.043, 0.078))
    ctx.addPath(roundedRect(card, radius: cardRadius))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    ctx.saveGState()
    ctx.addPath(roundedRect(card, radius: cardRadius))
    ctx.clip()
    drawPNG(fuji, in: card, ctx: ctx)
    ctx.restoreGState()

    let lensCenter = CGPoint(x: card.maxX - 178, y: card.maxY - 158)
    let lensRadius: CGFloat = 172
    let handleAngle: CGFloat = .pi / 4.15
    let handleLength: CGFloat = 210
    let handleWidth: CGFloat = 54

    ctx.saveGState()
    ctx.translateBy(x: lensCenter.x, y: lensCenter.y)
    ctx.rotate(by: handleAngle)
    let handleRect = CGRect(x: lensRadius - 18, y: -handleWidth / 2, width: handleLength, height: handleWidth)
    let handlePath = roundedRect(handleRect, radius: handleWidth / 2)
    ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 16, color: color(0, 0, 0, 0.4))
    ctx.addPath(handlePath)
    ctx.setFillColor(color(0.82, 0.88, 0.92))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(handlePath)
    ctx.setStrokeColor(color(0.55, 0.64, 0.72))
    ctx.setLineWidth(3)
    ctx.strokePath()
    let innerHandle = handleRect.insetBy(dx: 9, dy: 13)
    ctx.addPath(roundedRect(innerHandle, radius: innerHandle.height / 2))
    ctx.setFillColor(color(0.62, 0.71, 0.78))
    ctx.fillPath()
    ctx.restoreGState()

    let lensRect = CGRect(
        x: lensCenter.x - lensRadius,
        y: lensCenter.y - lensRadius,
        width: lensRadius * 2,
        height: lensRadius * 2
    )
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 22, color: color(0, 0, 0, 0.45))
    ctx.setFillColor(color(0.08, 0.14, 0.20))
    ctx.fillEllipse(in: lensRect)
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    let glass = lensRect.insetBy(dx: 24, dy: 24)
    ctx.saveGState()
    ctx.addEllipse(in: glass)
    ctx.clip()
    let focus = CGPoint(x: card.midX, y: card.minY + card.height * 0.30)
    ctx.translateBy(x: lensCenter.x, y: lensCenter.y)
    ctx.scaleBy(x: 1.35, y: 1.35)
    ctx.translateBy(x: -focus.x, y: -focus.y)
    drawPNG(fuji, in: card, ctx: ctx)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addEllipse(in: glass)
    ctx.clip()
    let highlight = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            color(1, 1, 1, 0.42),
            color(1, 1, 1, 0.08),
            color(1, 1, 1, 0.0),
        ] as CFArray,
        locations: [0, 0.45, 1]
    )!
    ctx.drawRadialGradient(
        highlight,
        startCenter: CGPoint(x: lensCenter.x - 48, y: lensCenter.y - 54),
        startRadius: 2,
        endCenter: lensCenter,
        endRadius: lensRadius - 28,
        options: []
    )
    ctx.restoreGState()

    ctx.setStrokeColor(color(0.90, 0.94, 0.97))
    ctx.setLineWidth(22)
    ctx.strokeEllipse(in: lensRect.insetBy(dx: 11, dy: 11))
    ctx.setStrokeColor(color(0.45, 0.55, 0.64))
    ctx.setLineWidth(4)
    ctx.strokeEllipse(in: lensRect.insetBy(dx: 22, dy: 22))
    ctx.setStrokeColor(color(1, 1, 1, 0.35))
    ctx.setLineWidth(3)
    ctx.strokeEllipse(in: glass.insetBy(dx: 2, dy: 2))

    return true
}

let out = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("QLMark-1024.png")

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    fputs("failed to encode PNG\n", stderr)
    exit(1)
}
try png.write(to: out)
print("wrote \(out.path)")
