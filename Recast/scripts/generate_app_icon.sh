#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPICONSET_DIR="$SCRIPT_DIR/../Recast/Assets.xcassets/AppIcon.appiconset"
MASTER_ICON="$(mktemp /tmp/recast-app-icon.XXXXXX.png)"

cleanup() {
    rm -f "$MASTER_ICON"
}
trap cleanup EXIT

RECAST_ICON_MASTER="$MASTER_ICON" xcrun swift - <<'SWIFT'
import AppKit
import Foundation

let outputPath = ProcessInfo.processInfo.environment["RECAST_ICON_MASTER"]!
let outputURL = URL(fileURLWithPath: outputPath)
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

let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.10)
shadow.shadowBlurRadius = 36
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()

let tileRect = NSRect(x: 72, y: 72, width: 880, height: 880)
let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 190, yRadius: 190)
NSColor.white.setFill()
tilePath.fill()

NSGraphicsContext.restoreGraphicsState()
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let strokePath = NSBezierPath(
    roundedRect: tileRect.insetBy(dx: 0.5, dy: 0.5),
    xRadius: 189.5,
    yRadius: 189.5
)
NSColor(calibratedWhite: 0.0, alpha: 0.06).setStroke()
strokePath.lineWidth = 1
strokePath.stroke()

let accent = NSColor(srgbRed: 0.345, green: 0.400, blue: 0.996, alpha: 1.0)
let configuration = NSImage.SymbolConfiguration(pointSize: 713, weight: .regular)
    .applying(.init(paletteColors: [accent]))

guard let symbol = NSImage(
    systemSymbolName: "waveform.circle",
    accessibilityDescription: nil
)?.withSymbolConfiguration(configuration) else {
    fatalError("Unable to create waveform.circle symbol")
}

// Keep some breathing room, but let the mark fill more of the tile.
let symbolRect = NSRect(x: 121, y: 121, width: 782, height: 782)
symbol.draw(in: symbolRect)

NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode PNG")
}
try data.write(to: outputURL, options: .atomic)
SWIFT

sips -z 16 16 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-16.png" >/dev/null
sips -z 32 32 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-16@2x.png" >/dev/null
sips -z 32 32 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-32.png" >/dev/null
sips -z 64 64 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-32@2x.png" >/dev/null
sips -z 128 128 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-128.png" >/dev/null
sips -z 256 256 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-128@2x.png" >/dev/null
sips -z 256 256 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-256.png" >/dev/null
sips -z 512 512 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-256@2x.png" >/dev/null
sips -z 512 512 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-512.png" >/dev/null
sips -z 1024 1024 "$MASTER_ICON" --out "$APPICONSET_DIR/app-icon-512@2x.png" >/dev/null
