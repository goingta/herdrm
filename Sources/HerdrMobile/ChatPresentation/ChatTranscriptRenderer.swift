import Foundation
import ImageIO
import SwiftUI
import UIKit
import WebKit

/// Display-only data. Service credentials and service URLs never enter the document.
struct ChatRenderPart: Codable, Equatable {
    var kind: String
    var text: String? = nil
    var phase: String? = nil
    var name: String? = nil
    var summary: String? = nil
    var input: String? = nil
    var output: String? = nil
    var ref: String? = nil
}

struct ChatRenderTurn: Codable, Equatable {
    var role: String
    var timestamp: String?
    var parts: [ChatRenderPart]
    var key: String? = nil
}

struct ChatRenderDocument: Codable, Equatable {
    var targetKey: String
    var historyID: String?
    var revision: String
    var source: String
    var turns: [ChatRenderTurn]
    var hasOlder = false
    var historyLimited = false
    var prepended = false
    var readinessAllowed = true
    var freshContent = false
    var theme = "dark"
    var language = "en"
    var textScale: Double = 1
    var labels: [String: String] = [:]
    var restoreScroll: Double? = nil
    var restoreFolds: [String]? = nil
}

struct ChatRendererProof: Equatable {
    let targetKey: String
    let historyID: String?
    let revision: String
}

/// A retained, offline transcript document. Navigation stays native and the bridge carries
/// only bounded display actions; HTTP authentication belongs exclusively to WebChatService.
@MainActor
final class ChatTranscriptRenderer: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var onPresented: ((ChatRendererProof) -> Void)?
    var onVisibleLatestReply: ((ChatRendererProof) -> Void)?
    var onLoadOlder: (() -> Void)?
    var onReload: (() -> Void)?
    var onUnavailable: (() -> Void)?
    var onImage: ((String, String, ChatRendererProof) -> Void)?
    var onToolOutput: ((String, String, ChatRendererProof) -> Void)?
    var onOpenURL: ((URL) -> Void)?
    private(set) var document: ChatRenderDocument?
    private var loaded = false
    private var visible = false
    private var bridge: TranscriptBridge!
    private var pageID = UUID().uuidString
    private var scrollTop: Double?
    private var folds: [String] = []
    private var restorePending = false
    private var automaticReloads = 0
    private var lastTermination: Date?
    private(set) var requiresReload = false

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        bridge = TranscriptBridge(owner: self)
        configuration.userContentController.add(bridge, name: "transcript")
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.accessibilityIdentifier = "chat.transcript"
        loadPage()
    }

    private func loadPage() {
        guard let url = Bundle.main.url(forResource: "transcript", withExtension: "html", subdirectory: "ChatPresentation"),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        loaded = false
        pageID = UUID().uuidString
        components.fragment = pageID
        guard let address = components.url else { return }
        webView.loadFileURL(address, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    /// Recovers the offline document after WebContent loss without treating cached content
    /// as newly presented. Fold/viewport context is bounded and retained natively.
    func reloadRetainingContext() {
        automaticReloads = 0
        recoverPage()
    }

    private func recoverPage() {
        requiresReload = false
        loaded = false
        pageID = UUID().uuidString
        restorePending = true
        document?.readinessAllowed = false
        document?.freshContent = false
        onReload?()
        loadPage()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loaded = false
        if let previous = lastTermination, Date().timeIntervalSince(previous) > 60 { automaticReloads = 0 }
        lastTermination = Date()
        guard automaticReloads < 3 else {
            requiresReload = true
            document?.readinessAllowed = false
            onUnavailable?()
            return
        }
        automaticReloads += 1
        recoverPage()
    }

    func present(_ document: ChatRenderDocument) {
        if self.document?.targetKey != document.targetKey || self.document?.historyID != document.historyID {
            scrollTop = nil; folds = []
        }
        self.document = document
        if loaded { publish() }
    }

    func setVisible(_ visible: Bool) {
        self.visible = visible
        if loaded { call("setVisible", arguments: [visible]) }
    }

    func requestVisibleProof() { if loaded { call("requestProof", arguments: []) } }

    func displayImage(_ data: Data, contentType: String, key: String, ref: String? = nil, proof: ChatRendererProof) {
        guard matchesReference(key: key, ref: ref, proof: proof),
              ["image/png", "image/jpeg", "image/gif", "image/webp", "image/avif", "image/heic"].contains(contentType),
              data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Double,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Double,
              width > 0, height > 0, width * height <= 40_000_000,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1600,
                  kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary), let png = UIImage(cgImage: thumbnail).pngData(), png.count <= 8 * 1024 * 1024 else { return }
        call("image", arguments: [key, png.base64EncodedString(), "image/png"])
    }

    func displayToolOutput(_ text: String, key: String, ref: String? = nil, proof: ChatRendererProof) {
        guard matchesReference(key: key, ref: ref, proof: proof) else { return }
        call("tool", arguments: [key, String(text.prefix(500_000))])
    }

    func displayReferenceError(_ message: String, key: String, ref: String? = nil, proof: ChatRendererProof) {
        guard matchesReference(key: key, ref: ref, proof: proof) else { return }
        call("error", arguments: [key, message])
    }

    private func matchesReference(key: String, ref: String?, proof: ChatRendererProof) -> Bool {
        guard let document, document.targetKey == proof.targetKey, document.historyID == proof.historyID else { return false }
        guard let ref else { return matches(proof) }
        // A poll changes the document revision without changing a validated opaque ref.
        // The exact part key/ref must still belong to the currently displayed history.
        for (index, turn) in document.turns.enumerated() {
            for (partIndex, part) in turn.parts.enumerated() {
                let partKey = "\(turn.key ?? turn.timestamp ?? String(index)):\(partIndex):\(part.kind)"
                if key == partKey && ref == part.ref { return true }
            }
        }
        return false
    }

    private func matches(_ proof: ChatRendererProof) -> Bool {
        document.map { $0.targetKey == proof.targetKey && $0.historyID == proof.historyID && $0.revision == proof.revision } ?? false
    }

    private func publish() {
        guard var document else { return }
        if restorePending { document.restoreScroll = scrollTop; document.restoreFolds = folds; restorePending = false }
        guard let data = try? JSONEncoder().encode(document),
              let object = try? JSONSerialization.jsonObject(with: data) else { return }
        call("present", arguments: [object])
        call("setVisible", arguments: [visible])
    }

    private func call(_ function: String, arguments: [Any]) {
        // Arguments are passed through WebKit's structured serialization, never interpolated
        // into executable script or HTML.
        var bindings: [String: Any] = [:]
        for (index, value) in arguments.enumerated() { bindings["arg\(index)"] = value }
        let names = arguments.indices.map { "arg\($0)" }.joined(separator: ",")
        webView.callAsyncJavaScript("window.herdrTranscript.\(function)(\(names))", arguments: bindings, in: nil, in: .page, completionHandler: { _ in })
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let kind = body["kind"] as? String, body["pageID"] as? String == pageID else { return }
        if kind == "loaded" { loaded = true; publish(); return }
        guard let targetKey = body["targetKey"] as? String, let revision = body["revision"] as? String else { return }
        let proof = ChatRendererProof(targetKey: targetKey, historyID: body["historyID"] as? String, revision: revision)
        guard matches(proof) else { return }
        switch kind {
        case "context":
            if let top = body["scrollTop"] as? Double, top.isFinite, top >= 0, top <= 100_000_000 { scrollTop = top }
            if let keys = body["folds"] as? [String] { folds = Array(keys.filter { $0.count <= 256 }.prefix(128)) }
        case "visibleLatest":
            guard visible, webView.window != nil, document?.freshContent == true else { return }
            onVisibleLatestReply?(proof)
        case "presented":
            guard visible, webView.window != nil, document?.readinessAllowed == true, document?.source != "scrollback" else { return }
            onPresented?(proof)
        case "older": onLoadOlder?()
        case "copy":
            if let text = body["text"] as? String, text.utf8.count <= 4_000_000 {
                UIPasteboard.general.string = text
                if let key = body["key"] as? String, key.count <= 32 { call("copied", arguments: [key]) }
            }
        case "image", "tool":
            guard let ref = body["ref"] as? String, ref.count <= 4096, let key = body["key"] as? String else { return }
            if kind == "image" { onImage?(ref, key, proof) } else { onToolOutput?(ref, key, proof) }
        case "link":
            guard let address = body["url"] as? String, let url = URL(string: address),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil, url.user == nil, url.password == nil else { return }
            onOpenURL?(url)
        default: break
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only the bundled initial document may navigate. Transcript links are native actions.
        let bundled = Bundle.main.url(forResource: "transcript", withExtension: "html", subdirectory: "ChatPresentation")
        decisionHandler(navigationAction.request.url?.isFileURL == true && navigationAction.request.url?.path == bundled?.path ? .allow : .cancel)
    }
}

@MainActor
private final class TranscriptBridge: NSObject, WKScriptMessageHandler {
    weak var owner: ChatTranscriptRenderer?
    init(owner: ChatTranscriptRenderer) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.receive(message) }
}

struct ChatTranscriptView: UIViewRepresentable {
    let renderer: ChatTranscriptRenderer
    func makeUIView(context: Context) -> WKWebView { renderer.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
