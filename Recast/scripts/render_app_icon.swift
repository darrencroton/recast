import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("Usage: render_app_icon.swift <output-path>\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let canvasSize = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
bitmap.size = canvasSize

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("Unable to create graphics context")
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let tileRect = NSRect(x: 40, y: 40, width: 944, height: 944)
let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 220, yRadius: 220)

func color(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1.0) -> NSColor {
    NSColor(srgbRed: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
}

func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat, lineCap: NSBezierPath.LineCapStyle = .round) {
    color.setStroke()
    path.lineWidth = width
    path.lineCapStyle = lineCap
    path.lineJoinStyle = .round
    path.stroke()
}

func fill(_ path: NSBezierPath, color: NSColor) {
    color.setFill()
    path.fill()
}

func fillCircle(center: CGPoint, radius: CGFloat, color: NSColor) {
    let circle = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    fill(circle, color: color)
}

let backgroundTop = color(74, 201, 169)
let backgroundBottom = color(22, 138, 130)
let outerArcColor = NSColor.white
let innerArcColor = color(182, 255, 232)
let waveColor = color(12, 110, 109, 0.45)
let centerColor = color(239, 252, 249)
let outlineColor = color(255, 255, 255, 0.18)

func drawGradientTile() {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 42
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()

    let gradient = NSGradient(colors: [backgroundTop, backgroundBottom])!
    gradient.draw(in: tilePath, angle: 90)

    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let highlight = NSBezierPath(roundedRect: tileRect.insetBy(dx: 2, dy: 2), xRadius: 218, yRadius: 218)
    stroke(highlight, color: outlineColor, width: 3)
}

func drawWaveBars(center: CGPoint, color: NSColor, barWidth: CGFloat, gap: CGFloat, heights: [CGFloat]) {
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    let startX = center.x - totalWidth / 2
    for (index, height) in heights.enumerated() {
        let x = startX + CGFloat(index) * (barWidth + gap)
        let rect = NSRect(x: x, y: center.y - height / 2, width: barWidth, height: height)
        let bar = NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2)
        fill(bar, color: color)
    }
}

func drawArrowLoop(center: CGPoint, radius: CGFloat) {
    let clockwise = NSBezierPath()
    clockwise.appendArc(withCenter: center, radius: radius, startAngle: 135, endAngle: 338, clockwise: false)
    stroke(clockwise, color: outerArcColor, width: 52)

    let clockwiseHead = NSBezierPath()
    clockwiseHead.move(to: CGPoint(x: center.x + radius + 12, y: center.y - 34))
    clockwiseHead.line(to: CGPoint(x: center.x + radius - 84, y: center.y - 12))
    clockwiseHead.line(to: CGPoint(x: center.x + radius - 20, y: center.y + 54))
    clockwiseHead.close()
    fill(clockwiseHead, color: outerArcColor)

    let counter = NSBezierPath()
    counter.appendArc(withCenter: center, radius: radius - 108, startAngle: 332, endAngle: 138, clockwise: true)
    stroke(counter, color: innerArcColor, width: 46)

    let counterHead = NSBezierPath()
    counterHead.move(to: CGPoint(x: center.x - radius + 54, y: center.y + 16))
    counterHead.line(to: CGPoint(x: center.x - radius + 138, y: center.y - 26))
    counterHead.line(to: CGPoint(x: center.x - radius + 114, y: center.y + 82))
    counterHead.close()
    fill(counterHead, color: innerArcColor)
}

drawGradientTile()
drawArrowLoop(center: CGPoint(x: 512, y: 532), radius: 290)
drawWaveBars(center: CGPoint(x: 512, y: 512), color: waveColor, barWidth: 36, gap: 24, heights: [88, 188, 280, 188, 88])
fillCircle(center: CGPoint(x: 512, y: 512), radius: 62, color: centerColor)

NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode PNG")
}

try data.write(to: outputURL, options: .atomic)
