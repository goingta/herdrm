import Foundation
import Network
import Testing
@testable import HerdrSSH

@Suite("HTTP CONNECT public connection", .serialized, .timeLimit(.minutes(2)))
struct HTTPConnectTests {
    @Test("CONNECT preserves the immediate SSH banner and supports authentication and exec",
          .enabled(if: SessionDriverTestEnvironment.current != nil || SessionDriverTestEnvironment.isRequired,
                   "requires the disposable sshd fixture"))
    func authenticatedTunnel() async throws {
        let environment = try #require(SessionDriverTestEnvironment.current)
        let gateway = try await ConnectGatewayFixture.start(response: nil, forward: environment.endpoint)
        defer { gateway.stop() }
        let direct = try await environment.connect()
        let connection = try await SSHConnection.connect(to: environment.endpoint, via: gateway.endpoint, timeout: .seconds(5))
        #expect(connection.hostKey == direct.hostKey, "The gateway must not substitute for target SSH verification")
        try await environment.authenticate(connection)
        let result = try await connection.execute("printf connect-through-gateway", timeout: .seconds(5))
        #expect(result.stdout == Data("connect-through-gateway".utf8))
        #expect(result.exitStatus == 0)
        try await connection.close(timeout: .seconds(2))
        try await direct.close(timeout: .seconds(2))
        try await gateway.expectPeerClosed()
    }

    @Test("a silent gateway expires within the connection deadline and releases its socket")
    func timeout() async throws {
        let gateway = try await ConnectGatewayFixture.start(response: nil)
        defer { gateway.stop() }
        let start = ContinuousClock.now
        await #expect(throws: SSHError.httpConnectTimedOut) {
            _ = try await SSHConnection.connect(to: .init(host: "dev.example"), via: gateway.endpoint, timeout: .milliseconds(150))
        }
        #expect(start.duration(to: .now) < .seconds(2))
        try await gateway.expectPeerClosed()
    }

    @Test("cancelling a pending CONNECT closes the gateway connection")
    func cancelled() async throws {
        let gateway = try await ConnectGatewayFixture.start(response: nil)
        defer { gateway.stop() }
        let task = Task { try await SSHConnection.connect(to: .init(host: "dev.example"), via: gateway.endpoint, timeout: .seconds(10)) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while gateway.request.isEmpty, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!gateway.request.isEmpty)
        task.cancel()
        await #expect(throws: SSHError.cancelled) { try await task.value }
        try await gateway.expectPeerClosed()
    }

    @Test("IPv6 target authority is bracketed in the CONNECT request")
    func ipv6Target() async throws {
        let gateway = try await ConnectGatewayFixture.start(response: Data("HTTP/1.0 502 Bad Gateway\r\n\r\n".utf8))
        defer { gateway.stop() }
        await #expect(throws: SSHError.httpConnectRejected(status: 502)) {
            _ = try await SSHConnection.connect(to: .init(host: "2001:db8::1", port: 2222), via: gateway.endpoint, timeout: .seconds(3))
        }
        #expect(gateway.request == "CONNECT [2001:db8::1]:2222 HTTP/1.1\r\nHost: [2001:db8::1]:2222\r\n\r\n")
        try await gateway.expectPeerClosed()
    }

    @Test("invalid target cannot inject headers or include a second port", arguments: ["dev.example\r\nX-Injected: yes", "dev.example:22", "https://dev.example"])
    func invalidTarget(host: String) async throws {
        let gateway = try await ConnectGatewayFixture.start(response: nil)
        defer { gateway.stop() }
        await #expect(throws: SSHError.invalidEndpoint) {
            _ = try await SSHConnection.connect(to: .init(host: host), via: gateway.endpoint, timeout: .seconds(3))
        }
        #expect(gateway.request.isEmpty)
    }

    @Test("oversized headers cannot consume an unbounded response")
    func oversizedHeader() async throws {
        let gateway = try await ConnectGatewayFixture.start(response: Data(("HTTP/1.1 200 OK\r\nX-Large: " + String(repeating: "x", count: 16_384)).utf8))
        defer { gateway.stop() }
        await #expect(throws: SSHError.invalidHTTPConnectResponse) {
            _ = try await SSHConnection.connect(to: .init(host: "dev.example"), via: gateway.endpoint, timeout: .seconds(3))
        }
        try await gateway.expectPeerClosed()
    }

    @Test("malformed response header values are rejected before SSH")
    func malformedHeader() async throws {
        let gateway = try await ConnectGatewayFixture.start(response: Data("HTTP/1.1 200 OK\r\nX-Gateway: \u{0}\r\n\r\n".utf8))
        defer { gateway.stop() }
        await #expect(throws: SSHError.invalidHTTPConnectResponse) {
            _ = try await SSHConnection.connect(to: .init(host: "dev.example"), via: gateway.endpoint, timeout: .milliseconds(300))
        }
        try await gateway.expectPeerClosed()
    }

    @Test("a refusing gateway reports its HTTP status and closes the socket")
    func rejected() async throws {
        let gateway = try await ConnectGatewayFixture.start(response: Data("HTTP/1.1 403 Forbidden\r\n\r\n".utf8))
        defer { gateway.stop() }
        await #expect(throws: SSHError.httpConnectRejected(status: 403)) {
            _ = try await SSHConnection.connect(to: .init(host: "dev.example", port: 22),
                via: gateway.endpoint, timeout: .seconds(3))
        }
        try await gateway.expectPeerClosed()
        #expect(gateway.request == "CONNECT dev.example:22 HTTP/1.1\r\nHost: dev.example:22\r\n\r\n")
    }
}

/// A real listening TCP gateway at the network boundary, not an SSH mock.
final class ConnectGatewayFixture: @unchecked Sendable {
    let listener: NWListener
    let queue = DispatchQueue(label: "herdr.connect.fixture")
    private let lock = NSLock()
    private var receivedRequest = ""
    private var peerClosed = false
    private var connections: [NWConnection] = []
    var request: String { lock.withLock { receivedRequest } }
    var endpoint: SSHEndpoint { .init(host: "127.0.0.1", port: listener.port!.rawValue) }
    private init(listener: NWListener) { self.listener = listener }

    static func start(response: Data?, forward: SSHEndpoint? = nil) async throws -> ConnectGatewayFixture {
        let fixture = ConnectGatewayFixture(listener: try NWListener(using: .tcp, on: .any))
        fixture.listener.newConnectionHandler = { connection in
            fixture.lock.withLock { fixture.connections.append(connection) }
            connection.start(queue: fixture.queue)
            fixture.receiveHeader(connection, bytes: Data(), response: response, forward: forward)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            fixture.listener.stateUpdateHandler = { state in
                switch state {
                case .ready: fixture.listener.stateUpdateHandler = nil; continuation.resume()
                case .failed(let error): fixture.listener.stateUpdateHandler = nil; continuation.resume(throwing: error)
                default: break
                }
            }
            fixture.listener.start(queue: fixture.queue)
        }
        return fixture
    }

    private func receiveHeader(_ connection: NWConnection, bytes: Data, response: Data?, forward: SSHEndpoint?) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, complete, error in
            var bytes = bytes
            if let data { bytes.append(data) }
            if bytes.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.lock.withLock { self.receivedRequest = String(decoding: bytes, as: UTF8.self) }
                if let forward { self.openTunnel(connection, target: forward); return }
                if let response { connection.send(content: response, completion: .contentProcessed { _ in }) }
                self.watchClosure(connection)
            } else if complete || error != nil { self.lock.withLock { self.peerClosed = true } }
            else { self.receiveHeader(connection, bytes: bytes, response: response, forward: forward) }
        }
    }

    private func openTunnel(_ client: NWConnection, target: SSHEndpoint) {
        let server = NWConnection(host: NWEndpoint.Host(target.host), port: NWEndpoint.Port(rawValue: target.port)!, using: .tcp)
        lock.withLock { connections.append(server) }
        server.stateUpdateHandler = { state in
            switch state {
            case .ready:
                server.stateUpdateHandler = nil
                // Intentionally coalesce the HTTP header and the real sshd's
                // first banner bytes in one send to exercise the boundary.
                server.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { banner, _, complete, error in
                    guard let banner, !banner.isEmpty, error == nil, !complete else { client.cancel(); return }
                    client.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8) + banner,
                                completion: .contentProcessed { error in
                        guard error == nil else { client.cancel(); server.cancel(); return }
                        self.pipe(client, to: server)
                        self.pipe(server, to: client)
                    })
                }
            case .failed: client.cancel(); server.cancel()
            default: break
            }
        }
        server.start(queue: queue)
    }

    private func pipe(_ source: NWConnection, to target: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, complete, error in
            if let data, !data.isEmpty {
                target.send(content: data, completion: .contentProcessed { sendError in
                    if sendError == nil, !complete, error == nil { self.pipe(source, to: target) }
                    else { self.lock.withLock { self.peerClosed = true }; source.cancel(); target.cancel() }
                })
            } else if complete || error != nil {
                self.lock.withLock { self.peerClosed = true }; source.cancel(); target.cancel()
            } else { self.pipe(source, to: target) }
        }
    }

    private func watchClosure(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, complete, error in
            if complete || error != nil { self.lock.withLock { self.peerClosed = true } }
            else { self.watchClosure(connection) }
        }
    }

    func expectPeerClosed() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !lock.withLock({ peerClosed }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(lock.withLock { peerClosed }, "Failed negotiation must release its gateway TCP connection")
    }

    func stop() {
        listener.cancel()
        for connection in lock.withLock({ connections }) { connection.cancel() }
    }
}
