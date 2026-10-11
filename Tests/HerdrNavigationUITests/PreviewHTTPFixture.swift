import Foundation
import Network

/// Disposable loopback server inside the UI test runner; works on Simulator and
/// physical iPhone. Only test HTML is served, no external project or credentials.
final class PreviewHTTPFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "herdr.visual.preview.fixture")
    let port: UInt16
    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters, on: .any)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
            if case .failed = state { ready.signal() }
        }
        listener.newConnectionHandler = { connection in
            connection.start(queue: DispatchQueue.global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                let second = String(data: data ?? Data(), encoding: .utf8)?.contains("GET /second") == true
                let content = second ? "<h1>VISUAL_SECOND_PAGE</h1>" : "<h1>VISUAL_PROJECT_PREVIEW</h1><p>项目网页保持自身样式。</p><a href='/second'>Second page</a>"
                let html = "<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'></head><body style='background:#f0f4ed;color:#142719;font:20px system-ui;padding:20px;overflow-wrap:anywhere'>\(content)</body></html>"
                let body = Data(html.utf8)
                var response = Data("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
                response.append(body)
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 3) == .success, let port = listener.port?.rawValue else {
            listener.cancel()
            throw NSError(domain: "PreviewHTTPFixture", code: 1)
        }
        self.port = port
    }
    deinit { listener.cancel() }
}
