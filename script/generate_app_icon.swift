// Generates the LithePG app icon master PNG (1024x1024).
//
// Regenerate the committed icon assets with:
//   swift script/generate_app_icon.swift packaging/AppIcon.png
//   mkdir -p /tmp/AppIcon.iconset
//   for s in 16 32 128 256 512; do
//     sips -z $s $s packaging/AppIcon.png --out /tmp/AppIcon.iconset/icon_${s}x${s}.png
//     d=$((s * 2))
//     sips -z $d $d packaging/AppIcon.png --out /tmp/AppIcon.iconset/icon_${s}x${s}@2x.png
//   done
//   iconutil -c icns /tmp/AppIcon.iconset -o packaging/AppIcon.icns

import AppKit
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift script/generate_app_icon.swift <output.png>\n".utf8))
    exit(2)
}
let outputURL = URL(fileURLWithPath: arguments[1])

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let context = CGContext(
    data: nil,
    width: size,
    height: size,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("error: could not create CGContext\n".utf8))
    exit(1)
}

// Background: macOS-style rounded square on the standard 1024 icon grid
// (824pt squircle centered, ~185pt corner radius), vertical blue gradient.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
context.addPath(platePath)
context.clip()

let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(srgbRed: 0.36, green: 0.62, blue: 1.00, alpha: 1.0),
        CGColor(srgbRed: 0.07, green: 0.26, blue: 0.66, alpha: 1.0),
    ] as CFArray,
    locations: [0.0, 1.0]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 512, y: plate.maxY),
    end: CGPoint(x: 512, y: plate.minY),
    options: []
)

// Glyph: simple white database cylinder (top ellipse + body + bottom cap),
// with two arc separators suggesting stacked disks.
let centerX: CGFloat = 512
let radiusX: CGFloat = 200
let radiusY: CGFloat = 64
let bodyTopY: CGFloat = 668
let bodyBottomY: CGFloat = 356

context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
context.fillEllipse(in: CGRect(
    x: centerX - radiusX, y: bodyTopY - radiusY, width: radiusX * 2, height: radiusY * 2
))
context.fill(CGRect(
    x: centerX - radiusX, y: bodyBottomY, width: radiusX * 2, height: bodyTopY - bodyBottomY
))
context.fillEllipse(in: CGRect(
    x: centerX - radiusX, y: bodyBottomY - radiusY, width: radiusX * 2, height: radiusY * 2
))

context.setStrokeColor(CGColor(srgbRed: 0.13, green: 0.36, blue: 0.80, alpha: 1.0))
context.setLineWidth(26)
context.setLineCap(.round)
for separatorY: CGFloat in [460, 564] {
    let arc = CGMutablePath()
    arc.move(to: CGPoint(x: centerX - radiusX + 13, y: separatorY))
    arc.addQuadCurve(
        to: CGPoint(x: centerX + radiusX - 13, y: separatorY),
        control: CGPoint(x: centerX, y: separatorY - radiusY * 2)
    )
    context.addPath(arc)
    context.strokePath()
}

guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          outputURL as CFURL, UTType.png.identifier as CFString, 1, nil
      )
else {
    FileHandle.standardError.write(Data("error: could not encode PNG\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("error: could not write \(outputURL.path)\n".utf8))
    exit(1)
}
