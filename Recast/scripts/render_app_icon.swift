import AppKit
import Foundation

struct Options {
    let outputURL: URL
    let canvasWidth: Int
    let opaqueBackground: Bool
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}

func parseOptions() -> Options {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let outputPath = arguments.first else {
        fail("Usage: render_app_icon.swift <output-path> [--size pixels] [--opaque]\n")
    }

    var canvasWidth = 1024
    var opaqueBackground = false
    var index = 1

    while index < arguments.count {
        switch arguments[index] {
        case "--size":
            guard index + 1 < arguments.count, let parsedWidth = Int(arguments[index + 1]), parsedWidth > 0 else {
                fail("Expected a positive integer after --size\n")
            }
            canvasWidth = parsedWidth
            index += 2
        case "--opaque":
            opaqueBackground = true
            index += 1
        default:
            fail("Unknown option: \(arguments[index])\n")
        }
    }

    return Options(
        outputURL: URL(fileURLWithPath: outputPath),
        canvasWidth: canvasWidth,
        opaqueBackground: opaqueBackground
    )
}

let options = parseOptions()
let canvasSize = NSSize(width: options.canvasWidth, height: options.canvasWidth)
let scale = CGFloat(options.canvasWidth) / 1024.0
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: options.canvasWidth,
    pixelsHigh: options.canvasWidth,
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

func scaled(_ value: CGFloat) -> CGFloat {
    value * scale
}

func color(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1.0) -> NSColor {
    NSColor(srgbRed: red / 255.0, green: green / 255.0, blue: blue / 255.0, alpha: alpha)
}

let backgroundTop = color(74, 201, 169)
let backgroundBottom = color(22, 138, 130)
let outerArcColor = NSColor.white
let innerArcColor = color(182, 255, 232)
let waveColor = color(12, 110, 109, 0.45)
let centerColor = color(239, 252, 249)
let outlineColor = color(255, 255, 255, 0.18)

let fullRect = NSRect(origin: .zero, size: canvasSize)
let tileRect = NSRect(
    x: scaled(40),
    y: scaled(40),
    width: scaled(944),
    height: scaled(944)
)
let tilePath = NSBezierPath(
    roundedRect: tileRect,
    xRadius: scaled(220),
    yRadius: scaled(220)
)

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
    let circle = NSBezierPath(
        ovalIn: NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
    )
    fill(circle, color: color)
}

func drawGradientTile() {
    if options.opaqueBackground {
        let backgroundGradient = NSGradient(colors: [backgroundTop, backgroundBottom])!
        backgroundGradient.draw(in: fullRect, angle: 90)
    }

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = scaled(42)
    shadow.shadowOffset = NSSize(width: 0, height: -scaled(18))
    shadow.set()

    let gradient = NSGradient(colors: [backgroundTop, backgroundBottom])!
    gradient.draw(in: tilePath, angle: 90)

    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let highlight = NSBezierPath(
        roundedRect: tileRect.insetBy(dx: scaled(2), dy: scaled(2)),
        xRadius: scaled(218),
        yRadius: scaled(218)
    )
    stroke(highlight, color: outlineColor, width: scaled(3))
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
    stroke(clockwise, color: outerArcColor, width: scaled(52))

    let clockwiseHead = NSBezierPath()
    clockwiseHead.move(to: CGPoint(x: center.x + radius + scaled(12), y: center.y - scaled(34)))
    clockwiseHead.line(to: CGPoint(x: center.x + radius - scaled(84), y: center.y - scaled(12)))
    clockwiseHead.line(to: CGPoint(x: center.x + radius - scaled(20), y: center.y + scaled(54)))
    clockwiseHead.close()
    fill(clockwiseHead, color: outerArcColor)

    let counter = NSBezierPath()
    counter.appendArc(withCenter: center, radius: radius - scaled(108), startAngle: 332, endAngle: 138, clockwise: true)
    stroke(counter, color: innerArcColor, width: scaled(46))

    let counterHead = NSBezierPath()
    counterHead.move(to: CGPoint(x: center.x - radius + scaled(54), y: center.y + scaled(16)))
    counterHead.line(to: CGPoint(x: center.x - radius + scaled(138), y: center.y - scaled(26)))
    counterHead.line(to: CGPoint(x: center.x - radius + scaled(114), y: center.y + scaled(82)))
    counterHead.close()
    fill(counterHead, color: innerArcColor)
}

drawGradientTile()
drawArrowLoop(center: CGPoint(x: canvasSize.width / 2, y: scaled(532)), radius: scaled(290))
drawWaveBars(
    center: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2),
    color: waveColor,
    barWidth: scaled(36),
    gap: scaled(24),
    heights: [scaled(88), scaled(188), scaled(280), scaled(188), scaled(88)]
)
fillCircle(center: CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2), radius: scaled(62), color: centerColor)

NSGraphicsContext.restoreGraphicsState()

let fileType: NSBitmapImageRep.FileType
let properties: [NSBitmapImageRep.PropertyKey: Any]
switch options.outputURL.pathExtension.lowercased() {
case "jpg", "jpeg":
    fileType = .jpeg
    properties = [.compressionFactor: 0.95]
default:
    fileType = .png
    properties = [:]
}

guard let data = bitmap.representation(using: fileType, properties: properties) else {
    fatalError("Unable to encode artwork")
}

try data.write(to: options.outputURL, options: .atomic)
