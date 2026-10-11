#if os(iOS)
import Foundation

/// Independent HTTPS system boundary. Production service validation and renderer remain real.
/// No network request, token, Keychain, user transcript or ATS exception is involved.
final class VisualChatHTTPBoundary: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "visual-chat-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let fixture = try VisualFixture.load()
            let url = request.url!
            let data: Data
            if url.path.hasSuffix("machines") {
                var snapshot = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.snapshot)) as! [String: Any]
                snapshot["protocol"] = 22
                let agents = snapshot["agents"] as! [[String: Any]]
                snapshot["panes"] = (snapshot["panes"] as? [[String: Any]] ?? []) + agents
                data = try JSONSerialization.data(withJSONObject: ["machines": [["id":"local", "name":fixture.deviceName, "kind":"local", "state":"connected", "enabled":true, "snapshot":snapshot]]])
            } else if url.path.hasSuffix("pane/conversation") {
                let resource = Bundle.main.url(forResource: "scene", withExtension: "json")!
                let scene = try JSONSerialization.jsonObject(with: Data(contentsOf: resource)) as! [String: Any]
                data = try JSONSerialization.data(withJSONObject: scene["conversation"]!)
            } else {
                throw URLError(.unsupportedURL)
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json", "ETag":"\"visual-v1\""])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
#endif
