#!/usr/bin/env swift
// Renders the AI-usage app icon (a usage gauge) into AppIcon.appiconset.
// Usage: swift scripts/make-app-icon.swift
import AppKit

let output = URL(fileURLWithPath: "AIUsage/Resources/Assets.xcassets/AppIcon.appiconset")

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(pixels) / 1024
    ctx.scaleBy(x: s, y: s)

    // macOS icon grid: 824pt rounded square centered in 1024, with a soft shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(shape)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let background = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(red: 0.16, green: 0.17, blue: 0.24, alpha: 1).cgColor,
        NSColor(red: 0.06, green: 0.06, blue: 0.10, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    ctx.restoreGState()

    // Gauge: 240° arc, track + colored fill to ~70 %.
    let center = CGPoint(x: 512, y: 470)
    let radius: CGFloat = 270
    let start = CGFloat.pi * 1.25, end = -CGFloat.pi * 0.25
    ctx.setLineCap(.round)
    ctx.setLineWidth(70)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor)
    ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    ctx.strokePath()

    let fillEnd = start - (start - end) * 0.7
    ctx.saveGState()
    ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: fillEnd, clockwise: true)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let accent = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(red: 0.30, green: 0.85, blue: 0.75, alpha: 1).cgColor,
        NSColor(red: 0.98, green: 0.62, blue: 0.30, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(accent, start: CGPoint(x: 200, y: 300), end: CGPoint(x: 800, y: 600), options: [])
    ctx.restoreGState()

    // Needle and hub.
    let needleAngle = fillEnd
    let tip = CGPoint(x: center.x + cos(needleAngle) * (radius - 70), y: center.y + sin(needleAngle) * (radius - 70))
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.setLineWidth(30)
    ctx.move(to: center)
    ctx.addLine(to: tip)
    ctx.strokePath()
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: center.x - 48, y: center.y - 48, width: 96, height: 96))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try! render(pixels: points * scale).write(to: output.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: output.appendingPathComponent("Contents.json"))
print("Wrote \(images.count) icon sizes to \(output.path)")
