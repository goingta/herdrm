import Foundation
import Observation
import WebKit

/// The preview owns its browser independently of the development-machine session.
/// Opening a page never changes an Agent selection or touches the SSH transport.
@MainActor
@Observable
final class ProjectPreviewBrowser: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private(set) var targetURL: URL?
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private var failure: Failure?
    private(set) var pageTitle = ""
    @ObservationIgnored private var requestedURL: URL?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    private enum Failure { case invalidAddress, tls, interrupted, network(String) }
    var errorMessage: String? {
        switch failure {
        case .invalidAddress: AppLocalization.string("Enter a full HTTP or HTTPS URL without embedded credentials.")
        case .tls: AppLocalization.string("The site's HTTPS certificate could not be verified.")
        case .interrupted: AppLocalization.string("The preview was interrupted. Reload to continue.")
        case .network(let reason): reason
        case nil: nil
        }
    }

    override init() {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.updateNavigationState() }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.updateNavigationState() }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.updateNavigationState() }
            },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.updateNavigationState() }
            },
            webView.observe(\.title, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.updateNavigationState() }
            },
        ]
    }

    @discardableResult
    func open(_ address: String) -> Bool {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: address),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              let url = components.url else {
            failure = .invalidAddress
            return false
        }
        requestedURL = url
        targetURL = url
        failure = nil
        isLoading = true
        webView.load(URLRequest(url: url))
        return true
    }

    func goBack() {
        guard webView.canGoBack else { return }
        failure = nil
        isLoading = true
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        failure = nil
        isLoading = true
        webView.goForward()
    }

    func reload() {
        failure = nil
        isLoading = requestedURL != nil || webView.url != nil
        if let requestedURL, requestedURL != webView.url {
            webView.load(URLRequest(url: requestedURL))
        } else if webView.url != nil {
            webView.reload()
        } else if let requestedURL {
            webView.load(URLRequest(url: requestedURL))
        }
    }

    private func updateNavigationState() {
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        pageTitle = webView.title ?? ""
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if case .invalidAddress = failure {} else { failure = nil }
        isLoading = true
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        targetURL = webView.url ?? targetURL
        requestedURL = targetURL
        updateNavigationState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        targetURL = webView.url ?? targetURL
        requestedURL = targetURL
        pageTitle = webView.title ?? ""
        updateNavigationState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showFailure(error)
    }

    private func showFailure(_ error: Error) {
        let error = error as NSError
        guard !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) else { return }
        isLoading = false
        let tlsCodes = [NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
                        NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
                        NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
                        NSURLErrorClientCertificateRequired]
        failure = error.domain == NSURLErrorDomain && tlsCodes.contains(error.code)
            ? .tls : .network(error.localizedDescription)
        updateNavigationState()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoading = false
        failure = .interrupted
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Subframes retain normal WebKit behavior (including about:blank and
        // blob content used by project pages). The address bar accepts web URLs.
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
            return
        }
        guard let url = navigationAction.request.url,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame != false {
            requestedURL = url
            targetURL = url
        }
        // Keep pages inside this browser even when a site requests a new window.
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
}
