// Generates the LithePG app icon master PNG (1024x1024).
//
// Regenerate both committed icon assets with:
//   swift script/generate_app_icon.swift packaging/AppIcon.png packaging/AppIcon.icns

import AppKit
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let arguments = CommandLine.arguments
guard arguments.count == 2 || arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("usage: swift script/generate_app_icon.swift <output.png> [output.icns]\n".utf8)
    )
    exit(2)
}
let outputURL = URL(fileURLWithPath: arguments[1])
let icnsOutputURL = arguments.count == 3 ? URL(fileURLWithPath: arguments[2]) : nil

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
// (824pt squircle centered, ~185pt corner radius), with a deep blue plate
// and a restrained center glow so the mark stays legible at small sizes.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
context.addPath(platePath)
context.clip()

let plateGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(srgbRed: 0.29, green: 0.67, blue: 1.00, alpha: 1.0),
        CGColor(srgbRed: 0.12, green: 0.35, blue: 0.88, alpha: 1.0),
        CGColor(srgbRed: 0.04, green: 0.10, blue: 0.36, alpha: 1.0),
    ] as CFArray,
    locations: [0.0, 0.52, 1.0]
)!
context.drawLinearGradient(
    plateGradient,
    start: CGPoint(x: 512, y: plate.maxY),
    end: CGPoint(x: 512, y: plate.minY),
    options: []
)

let plateGlow = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(srgbRed: 0.45, green: 0.90, blue: 1.00, alpha: 0.30),
        CGColor(srgbRed: 0.28, green: 0.48, blue: 1.00, alpha: 0.00),
    ] as CFArray,
    locations: [0.0, 1.0]
)!
context.drawRadialGradient(
    plateGlow,
    startCenter: CGPoint(x: 430, y: 650),
    startRadius: 0,
    endCenter: CGPoint(x: 430, y: 650),
    endRadius: 430,
    options: []
)

// Glyph: a luminous database cylinder (top ellipse + body + bottom cap),
// with two crisp arc separators suggesting stacked disks.
let centerX: CGFloat = 512
let radiusX: CGFloat = 200
let radiusY: CGFloat = 64
let bodyTopY: CGFloat = 668
let bodyBottomY: CGFloat = 356

let topEllipse = CGRect(
    x: centerX - radiusX, y: bodyTopY - radiusY, width: radiusX * 2, height: radiusY * 2
)
let bodyRect = CGRect(
    x: centerX - radiusX, y: bodyBottomY, width: radiusX * 2, height: bodyTopY - bodyBottomY
)
let bottomEllipse = CGRect(
    x: centerX - radiusX, y: bodyBottomY - radiusY, width: radiusX * 2, height: radiusY * 2
)
let databasePath = CGMutablePath()
databasePath.addEllipse(in: topEllipse)
databasePath.addRect(bodyRect)
databasePath.addEllipse(in: bottomEllipse)

// A soft shadow separates the database from the plate without muddying the
// transparent edge of the app icon.
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -14),
    blur: 30,
    color: CGColor(srgbRed: 0.01, green: 0.04, blue: 0.20, alpha: 0.42)
)
context.addPath(databasePath)
context.setFillColor(CGColor(srgbRed: 0.42, green: 0.76, blue: 1.00, alpha: 1.0))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(databasePath)
context.clip()

let databaseGradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(srgbRed: 0.91, green: 0.99, blue: 1.00, alpha: 1.0),
        CGColor(srgbRed: 0.31, green: 0.86, blue: 1.00, alpha: 1.0),
        CGColor(srgbRed: 0.20, green: 0.48, blue: 0.98, alpha: 1.0),
        CGColor(srgbRed: 0.43, green: 0.20, blue: 0.88, alpha: 1.0),
    ] as CFArray,
    locations: [0.0, 0.28, 0.66, 1.0]
)!
context.drawLinearGradient(
    databaseGradient,
    start: CGPoint(x: centerX, y: topEllipse.maxY),
    end: CGPoint(x: centerX, y: bottomEllipse.minY),
    options: []
)

let glyphGlow = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.52),
        CGColor(srgbRed: 0.75, green: 0.96, blue: 1.00, alpha: 0.00),
    ] as CFArray,
    locations: [0.0, 1.0]
)!
context.drawRadialGradient(
    glyphGlow,
    startCenter: CGPoint(x: 435, y: 665),
    startRadius: 0,
    endCenter: CGPoint(x: 435, y: 665),
    endRadius: 260,
    options: []
)
context.restoreGState()

context.setStrokeColor(CGColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.58))
context.setLineWidth(5)
context.strokeEllipse(in: topEllipse.insetBy(dx: 2.5, dy: 2.5))

context.setFillColor(CGColor(srgbRed: 0.04, green: 0.12, blue: 0.43, alpha: 0.72))
let separatorHalfWidth: CGFloat = 13
for separatorY: CGFloat in [460, 564] {
    let band = CGMutablePath()
    band.move(to: CGPoint(x: bodyRect.minX, y: separatorY + separatorHalfWidth))
    band.addQuadCurve(
        to: CGPoint(x: bodyRect.maxX, y: separatorY + separatorHalfWidth),
        control: CGPoint(x: centerX, y: separatorY - radiusY * 2 + separatorHalfWidth)
    )
    band.addLine(to: CGPoint(x: bodyRect.maxX, y: separatorY - separatorHalfWidth))
    band.addQuadCurve(
        to: CGPoint(x: bodyRect.minX, y: separatorY - separatorHalfWidth),
        control: CGPoint(x: centerX, y: separatorY - radiusY * 2 - separatorHalfWidth)
    )
    band.closeSubpath()
    context.addPath(band)
    context.fillPath()
}

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("error: could not render icon\n".utf8))
    exit(1)
}

enum IconGenerationError: Error {
    case couldNotCreateContext(Int)
    case couldNotRender(Int)
    case couldNotEncodePNG
    case malformedPNG
    case oversizedICNS
}

/// ImageIO currently adds EXIF metadata even when no properties are supplied.
/// Keep only deterministic chunks that the package verifier permits.
func cleanPNGData(for image: CGImage) throws -> Data {
    let encoded = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        encoded, UTType.png.identifier as CFString, 1, nil
    ) else {
        throw IconGenerationError.couldNotEncodePNG
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconGenerationError.couldNotEncodePNG
    }

    let raw = encoded as Data
    let signature = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
    guard raw.count >= signature.count, raw.prefix(signature.count) == signature else {
        throw IconGenerationError.malformedPNG
    }

    let allowedChunks: Set<String> = ["IHDR", "sRGB", "IDAT", "IEND"]
    var clean = signature
    var offset = signature.count
    var sawIEND = false
    while offset < raw.count {
        guard offset + 12 <= raw.count else { throw IconGenerationError.malformedPNG }
        let length = raw[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
        let chunkEnd = offset + 12 + length
        guard chunkEnd <= raw.count,
              let chunkType = String(data: raw[(offset + 4)..<(offset + 8)], encoding: .ascii)
        else {
            throw IconGenerationError.malformedPNG
        }
        if allowedChunks.contains(chunkType) {
            clean.append(raw[offset..<chunkEnd])
        }
        offset = chunkEnd
        if chunkType == "IEND" {
            sawIEND = true
            break
        }
    }
    guard sawIEND, offset == raw.count else { throw IconGenerationError.malformedPNG }
    return clean
}

func scaledImage(from source: CGImage, dimension: Int) throws -> CGImage {
    if dimension == source.width, dimension == source.height { return source }
    guard let scaledContext = CGContext(
        data: nil,
        width: dimension,
        height: dimension,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw IconGenerationError.couldNotCreateContext(dimension)
    }
    scaledContext.interpolationQuality = .high
    scaledContext.draw(source, in: CGRect(x: 0, y: 0, width: dimension, height: dimension))
    guard let scaled = scaledContext.makeImage() else {
        throw IconGenerationError.couldNotRender(dimension)
    }
    return scaled
}

func appendBigEndian(_ value: UInt32, to data: inout Data) {
    data.append(UInt8((value >> 24) & 0xff))
    data.append(UInt8((value >> 16) & 0xff))
    data.append(UInt8((value >> 8) & 0xff))
    data.append(UInt8(value & 0xff))
}

func icnsData(from source: CGImage) throws -> Data {
    let representations: [(type: String, dimension: Int)] = [
        ("icp4", 16),
        ("icp5", 32),
        ("icp6", 64),
        ("ic07", 128),
        ("ic08", 256),
        ("ic09", 512),
        ("ic10", 1024),
    ]
    var elements = Data()
    for representation in representations {
        let resized = try scaledImage(from: source, dimension: representation.dimension)
        let payload = try cleanPNGData(for: resized)
        guard let type = representation.type.data(using: .ascii),
              payload.count <= Int(UInt32.max) - 8
        else {
            throw IconGenerationError.oversizedICNS
        }
        elements.append(type)
        appendBigEndian(UInt32(payload.count + 8), to: &elements)
        elements.append(payload)
    }
    guard elements.count <= Int(UInt32.max) - 8 else {
        throw IconGenerationError.oversizedICNS
    }
    var container = Data("icns".utf8)
    appendBigEndian(UInt32(elements.count + 8), to: &container)
    container.append(elements)
    return container
}

do {
    try cleanPNGData(for: image).write(to: outputURL, options: .atomic)
    if let icnsOutputURL {
        try icnsData(from: image).write(to: icnsOutputURL, options: .atomic)
    }
} catch {
    FileHandle.standardError.write(Data("error: could not write icon assets: \(error)\n".utf8))
    exit(1)
}
