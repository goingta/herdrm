// Run from the repository root: swift Resources/AppIcon/generate-mobile-icon.swift
// Mechanical platform adaptation: preserve the canonical artwork, remove alpha.
import CoreGraphics
import Foundation
import ImageIO

let sourceURL = URL(fileURLWithPath: "Resources/AppIcon/herdrm-icon-1024.png")
let outputURL = URL(fileURLWithPath: "Resources/AppIcon/MobileAssets.xcassets/AppIcon.appiconset/herdrm-icon-1024.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
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
print("Generated opaque mobile AppIcon from canonical Mac artwork")
