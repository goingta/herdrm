import SwiftUI
#if os(macOS)
import AppKit
typealias NativeBrandImage = NSImage
#else
import UIKit
typealias NativeBrandImage = UIImage
#endif

/// Renders a bundled mono SVG brand icon (LobeHub agent icons, Simple Icons OS icons)
/// as a template image so it tints like SF Symbols.
struct BrandIcon: View {
    let resource: String
    var size: CGFloat = 12
    var fallbackSystemName: String = "terminal"

    var body: some View {
        if let image = BrandIconLoader.image(named: resource) {
            // Color variants keep their brand colors; mono ones tint like SF Symbols.
            nativeImage(image)
                .resizable()
                .renderingMode(resource.hasSuffix("-color") ? .original : .template)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallbackSystemName)
                .font(.system(size: size - 1))
        }
    }
    private func nativeImage(_ image: NativeBrandImage) -> Image {
        #if os(macOS)
        Image(nsImage: image)
        #else
        Image(uiImage: image)
        #endif
    }

}

enum BrandIconLoader {
    private static var cache: [String: NativeBrandImage?] = [:]
    private static let lock = NSLock()

    static func image(named name: String) -> NativeBrandImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[name] { return cached }
        #if os(macOS)
        var loaded: NativeBrandImage?
        if let url = Bundle.main.url(forResource: name, withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = !name.hasSuffix("-color")
            loaded = image
        }
        #else
        let loaded = UIImage(named: name)
        #endif
        cache[name] = loaded
        return loaded
    }

    #if os(macOS)
    /// A fixed-size template copy for AppKit menus (menu labels ignore SwiftUI frames).
    static func menuImage(named name: String, size: CGFloat = 14) -> NativeBrandImage? {
        guard let base = image(named: name) else { return nil }
        let sized = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            base.draw(in: rect)
            return true
        }
        sized.isTemplate = true
        return sized
    }

    #endif
    /// Maps a herdr agent kind ("claude", "codex", "grok", …) to a bundled icon resource,
    /// preferring the brand-color variant when one is bundled.
    static func agentIcon(for kind: String) -> String? {
        let normalized = kind.lowercased().replacingOccurrences(of: "_", with: "-")
        let map: [String: String] = [
            "claude": "claude", "claude-code": "claude",
            "codex": "codex",
            "grok": "grok",
            "cursor": "cursor", "cursor-agent": "cursor",
            "opencode": "opencode",
            "openai": "openai", "gpt": "openai",
            "gemini": "gemini",
            "deepseek": "deepseek",
            "qwen": "qwen", "qwen-code": "qwen",
            "copilot": "copilot", "github-copilot": "githubcopilot",
            "kimi": "kimi",
            "pi": "pi",
        ]
        var base: String?
        if let exact = map[normalized] {
            base = exact
        } else {
            // Suffixed kinds ("claude-code-next") fall back to their base mark.
            // Longest key first so "claude-code" outranks "claude" — a plain
            // dictionary walk picked an arbitrary one — and the "-" boundary
            // keeps a two-letter kind like "pi" from claiming "pilot".
            base = map
                .filter { normalized.hasPrefix("\($0.key)-") }
                .max { $0.key.count < $1.key.count }?
                .value
        }
        guard let base else { return nil }
        if image(named: "\(base)-color") != nil {
            return "\(base)-color"
        }
        return base
    }

    /// Maps a sniffed OS id ("macos", "ubuntu", "debian", …) to a bundled icon resource.
    static func osIcon(for osID: String?) -> String? {
        guard let os = osID?.lowercased(), !os.isEmpty else { return nil }
        let map: [String: String] = [
            "macos": "apple", "darwin": "apple",
            "ubuntu": "ubuntu",
            "debian": "debian",
            "fedora": "fedora",
            "arch": "archlinux", "archlinux": "archlinux",
            "alpine": "alpinelinux",
            "nixos": "nixos",
            "rocky": "rockylinux",
            "centos": "centos",
            "freebsd": "freebsd",
        ]
        if let exact = map[os] { return exact }
        if os.contains("linux") { return "linux" }
        return nil
    }
}
