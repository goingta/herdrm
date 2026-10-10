import CoreGraphics

/// A renderer snapshot with only a flat background is not viewed terminal
/// content. Samples the presented image, never an offscreen Ghostty text buffer.
enum TerminalFrameReadiness {
    static func containsRenderedContent(_ image: CGImage) -> Bool {
        let width = 96, height = 96
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            // A handful of high-contrast pixels excludes a uniform clear frame.
            let bytes = buffer.bindMemory(to: UInt8.self)
            let base = [bytes[0], bytes[1], bytes[2]]
            var distinct = 0
            for index in stride(from: 0, to: buffer.count, by: 4) {
                if (0..<3).contains(where: { abs(Int(bytes[index + $0]) - Int(base[$0])) > 32 }) {
                    distinct += 1
                    if distinct >= 12 { return true }
                }
            }
            return false
        }
    }
}
