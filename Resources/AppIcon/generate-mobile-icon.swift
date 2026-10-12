// Run from the repository root: swift Resources/AppIcon/generate-mobile-icon.swift
// Render the canonical SVG, then mechanically adapt it for each platform.
import AppKit
import CoreGraphics
import Foundation
import ImageIO

let sourceURL = URL(fileURLWithPath: "Resources/AppIcon/herdrm-icon.svg")
let canonicalURL = URL(fileURLWithPath: "Resources/AppIcon/herdrm-icon-1024.png")
let macURL = URL(fileURLWithPath: "Sources/HerdrM/AppIcon.icon/Assets/herdrm-icon-1024.png")
let previewURL = URL(fileURLWithPath: "Resources/AppIcon/herdrm-icon-rounded.png")
let outputURL = URL(fileURLWithPath: "Resources/AppIcon/MobileAssets.xcassets/AppIcon.appiconset/herdrm-icon-1024.png")
guard let artwork = NSImage(contentsOf: sourceURL) else { fatalError("Cannot read canonical SVG") }

func renderedPNG(size: Int, roundedPreview: Bool = false) -> Data {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
        let bitmapContext = CGContext(data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("Cannot render SVG")
    }
    let context = NSGraphicsContext(cgContext: bitmapContext, flipped: false)
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    if roundedPreview {
        // Documentation preview only; neither platform's AppIcon uses this mask.
        NSBezierPath(roundedRect: bounds, xRadius: CGFloat(size) * 0.22,
            yRadius: CGFloat(size) * 0.22).addClip()
    }
    artwork.draw(in: bounds)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let image = bitmapContext.makeImage(),
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode SVG render")
    }
    return png
}

let canonicalPNG = renderedPNG(size: 1024)
try canonicalPNG.write(to: canonicalURL)
try canonicalPNG.write(to: macURL)
try renderedPNG(size: 256, roundedPreview: true).write(to: previewURL)

// Preserve the sRGB artwork but remove alpha for the iOS full-square AppIcon.
guard let source = CGImageSourceCreateWithURL(canonicalURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width == 1024, image.height == 1024,
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: image.width, height: image.height,
          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
      let destination = CGImageDestinationCreateWithURL(outputURL as CFURL,
          "public.png" as CFString, 1, nil) else {
    fatalError("Cannot read canonical 1024px artwork or create mobile icon")
}
context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
guard let opaqueImage = context.makeImage() else { fatalError("Cannot render icon") }
CGImageDestinationAddImage(destination, opaqueImage, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save icon") }
print("Generated canonical/Mac artwork, documentation preview and opaque mobile AppIcon from SVG")
