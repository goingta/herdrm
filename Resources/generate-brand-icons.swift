// Run from repository root: swift Resources/generate-brand-icons.swift
// UIKit cannot decode the canonical SVGs; generate native assets without new artwork.
import AppKit
import Foundation

let root = URL(fileURLWithPath: "Resources/BrandIcons.xcassets", isDirectory: true)
let fm = FileManager.default
try fm.createDirectory(at: root, withIntermediateDirectories: true)
func json(_ value: Any, to url: URL) throws {
    try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}
let info: [String: Any] = ["author": "xcode", "version": 1]
try json(["info": info], to: root.appendingPathComponent("Contents.json"))
for folder in ["AgentIcons", "OSIcons"] {
    for source in try fm.contentsOfDirectory(at: URL(fileURLWithPath: "Resources/\(folder)"), includingPropertiesForKeys: nil).filter({ $0.pathExtension == "svg" }).sorted(by: { $0.path < $1.path }) {
        let name = source.deletingPathExtension().lastPathComponent
        let output = root.appendingPathComponent("\(name).imageset", isDirectory: true)
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        guard let image = NSImage(contentsOf: source),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 60, pixelsHigh: 60,
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot render \(source.path)") }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 60, height: 60))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode \(name)") }
        try png.write(to: output.appendingPathComponent("\(name)@3x.png"))
        try json(["info": info, "images": [["idiom": "universal", "scale": "3x", "filename": "\(name)@3x.png"]]],
                 to: output.appendingPathComponent("Contents.json"))
    }
}
print("Generated UIKit brand assets from canonical AgentIcons / OSIcons SVGs")
