import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_icon.swift <output_png_or_icns_path>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let size: CGFloat = 1024
let pixelSize = Int(size)

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(
          data: nil,
          width: pixelSize,
          height: pixelSize,
          bitsPerComponent: 8,
          bytesPerRow: 0,
          space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
else {
    fputs("Failed to create CGContext\n", stderr)
    exit(1)
}

// Flip coordinate system to top-left origin for intuitive drawing
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

// Background macOS icon squircle inset
let inset: CGFloat = 92
let iconRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let squircle = CGPath(roundedRect: iconRect, cornerWidth: 196, cornerHeight: 196, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()

let bgColors = [
    CGColor(red: 0.08, green: 0.09, blue: 0.13, alpha: 1.0),
    CGColor(red: 0.03, green: 0.035, blue: 0.05, alpha: 1.0)
] as CFArray
if let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: size / 2, y: iconRect.minY),
        end: CGPoint(x: size / 2, y: iconRect.maxY),
        options: []
    )
}

// Top notch pill motif inside icon
let notchW: CGFloat = 460
let notchH: CGFloat = 110
let notchX = (size - notchW) / 2
let notchY = iconRect.minY
let notchPath = CGMutablePath()
notchPath.move(to: CGPoint(x: notchX, y: notchY))
notchPath.addQuadCurve(to: CGPoint(x: notchX + 36, y: notchY + 36), control: CGPoint(x: notchX + 36, y: notchY))
notchPath.addLine(to: CGPoint(x: notchX + 36, y: notchY + notchH - 42))
notchPath.addQuadCurve(to: CGPoint(x: notchX + 78, y: notchY + notchH), control: CGPoint(x: notchX + 36, y: notchY + notchH))
notchPath.addLine(to: CGPoint(x: notchX + notchW - 78, y: notchY + notchH))
notchPath.addQuadCurve(to: CGPoint(x: notchX + notchW - 36, y: notchY + notchH - 42), control: CGPoint(x: notchX + notchW - 36, y: notchY + notchH))
notchPath.addLine(to: CGPoint(x: notchX + notchW - 36, y: notchY + 36))
notchPath.addQuadCurve(to: CGPoint(x: notchX + notchW, y: notchY), control: CGPoint(x: notchX + notchW - 36, y: notchY))
notchPath.closeSubpath()

ctx.setFillColor(CGColor(red: 0.015, green: 0.015, blue: 0.02, alpha: 1.0))
ctx.addPath(notchPath)
ctx.fillPath()

ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.14))
ctx.setLineWidth(4)
ctx.addPath(notchPath)
ctx.strokePath()

// Subtle amber ambient glow behind owl
let glowCenter = CGPoint(x: size / 2, y: size * 0.56)
let glowColors = [
    CGColor(red: 0.98, green: 0.74, blue: 0.22, alpha: 0.25),
    CGColor(red: 0.98, green: 0.74, blue: 0.22, alpha: 0.0)
] as CFArray
if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
    ctx.drawRadialGradient(
        glow,
        startCenter: glowCenter,
        startRadius: 20,
        endCenter: glowCenter,
        endRadius: 340,
        options: []
    )
}

// Geometric Owl Head
let owlRect = CGRect(x: 242, y: 278, width: 540, height: 520)
let ox = owlRect.minX
let oy = owlRect.minY
let ow = owlRect.width
let oh = owlRect.height

let head = CGMutablePath()
head.move(to: CGPoint(x: ox + ow * 0.20, y: oy + oh * 0.12))
head.addLine(to: CGPoint(x: ox + ow * 0.35, y: oy + oh * 0.24))
head.addQuadCurve(to: CGPoint(x: ox + ow * 0.65, y: oy + oh * 0.24), control: CGPoint(x: ox + ow * 0.5, y: oy + oh * 0.18))
head.addLine(to: CGPoint(x: ox + ow * 0.80, y: oy + oh * 0.12))
head.addQuadCurve(to: CGPoint(x: ox + ow * 0.87, y: oy + oh * 0.57), control: CGPoint(x: ox + ow * 0.91, y: oy + oh * 0.34))
head.addQuadCurve(to: CGPoint(x: ox + ow * 0.50, y: oy + oh * 0.92), control: CGPoint(x: ox + ow * 0.82, y: oy + oh * 0.88))
head.addQuadCurve(to: CGPoint(x: ox + ow * 0.13, y: oy + oh * 0.57), control: CGPoint(x: ox + ow * 0.18, y: oy + oh * 0.88))
head.addQuadCurve(to: CGPoint(x: ox + ow * 0.20, y: oy + oh * 0.12), control: CGPoint(x: ox + ow * 0.09, y: oy + oh * 0.34))
head.closeSubpath()

ctx.setFillColor(CGColor(red: 0.19, green: 0.21, blue: 0.28, alpha: 1.0))
ctx.addPath(head)
ctx.fillPath()

ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.24))
ctx.setLineWidth(8)
ctx.addPath(head)
ctx.strokePath()

// Eye sockets + Amber irises + Pupils + Specular glints
let eyeY = oy + oh * 0.50
let leftEye = CGPoint(x: ox + ow * 0.36, y: eyeY)
let rightEye = CGPoint(x: ox + ow * 0.64, y: eyeY)
let eyeR = ow * 0.155

for eye in [leftEye, rightEye] {
    let discR = eyeR * 1.28
    ctx.setFillColor(CGColor(red: 0.12, green: 0.14, blue: 0.19, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(x: eye.x - discR, y: eye.y - discR, width: discR * 2, height: discR * 2))

    ctx.setFillColor(CGColor(red: 0.98, green: 0.74, blue: 0.22, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(x: eye.x - eyeR, y: eye.y - eyeR, width: eyeR * 2, height: eyeR * 2))

    let pupilR = eyeR * 0.52
    ctx.setFillColor(CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(x: eye.x - pupilR, y: eye.y - pupilR, width: pupilR * 2, height: pupilR * 2))

    let glintR = eyeR * 0.21
    ctx.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.92))
    ctx.fillEllipse(in: CGRect(x: eye.x - eyeR * 0.36, y: eye.y - eyeR * 0.40, width: glintR * 2, height: glintR * 2))
}

// Geometric beak
let beak = CGMutablePath()
beak.move(to: CGPoint(x: ox + ow * 0.435, y: oy + oh * 0.60))
beak.addLine(to: CGPoint(x: ox + ow * 0.565, y: oy + oh * 0.60))
beak.addLine(to: CGPoint(x: ox + ow * 0.50, y: oy + oh * 0.72))
beak.closeSubpath()
ctx.setFillColor(CGColor(red: 0.96, green: 0.60, blue: 0.16, alpha: 1.0))
ctx.addPath(beak)
ctx.fillPath()

ctx.restoreGState()

// Outer squircle border
ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.16))
ctx.setLineWidth(4)
ctx.addPath(squircle)
ctx.strokePath()

guard let cgImage = ctx.makeImage() else {
    fputs("Failed to create CGImage\n", stderr)
    exit(1)
}

func makePNGData(from image: CGImage, pixelWidth: Int) -> Data? {
    if image.width == pixelWidth && image.height == pixelWidth {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }
    guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
          let scaledCtx = CGContext(
              data: nil,
              width: pixelWidth,
              height: pixelWidth,
              bitsPerComponent: 8,
              bytesPerRow: 0,
              space: cs,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          )
    else {
        return nil
    }
    scaledCtx.interpolationQuality = .high
    scaledCtx.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelWidth))
    guard let scaledImage = scaledCtx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: scaledImage)
    return rep.representation(using: .png, properties: [:])
}

let outputURL = URL(fileURLWithPath: outputPath)
if outputURL.pathExtension.lowercased() == "icns" {
    let entries: [(String, Int)] = [
        ("icp4", 16),
        ("ic11", 32),
        ("icp5", 32),
        ("ic12", 64),
        ("ic07", 128),
        ("ic13", 256),
        ("ic08", 256),
        ("ic14", 512),
        ("ic09", 512),
        ("ic10", 1024)
    ]

    var body = Data()
    for (tag, px) in entries {
        guard let png = makePNGData(from: cgImage, pixelWidth: px),
              let tagData = tag.data(using: .ascii), tagData.count == 4
        else { continue }
        var chunkLength = UInt32(8 + png.count).bigEndian
        body.append(tagData)
        body.append(Data(bytes: &chunkLength, count: 4))
        body.append(png)
    }

    var icns = Data("icns".utf8)
    var totalLength = UInt32(8 + body.count).bigEndian
    icns.append(Data(bytes: &totalLength, count: 4))
    icns.append(body)
    try icns.write(to: outputURL)
} else {
    guard let pngData = makePNGData(from: cgImage, pixelWidth: pixelSize) else {
        fputs("Failed to encode PNG\n", stderr)
        exit(1)
    }
    try pngData.write(to: outputURL)
}
