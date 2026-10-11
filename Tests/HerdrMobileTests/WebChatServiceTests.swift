import XCTest
@testable import HerdrMobile

final class WebChatServiceTests: XCTestCase {
    @MainActor
    func testServiceBindingPersistsWithoutCredentialsAndLegacyProfilesRemainUnbound() throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        var device = MobileDevice(name: "Linux", host: "linux.example", username: "developer")
        let binding = try WebChatConfiguration(serviceURL: "https://chat.example:5666/", machineID: "local")
        device.chatConfiguration = binding
        store.save([device])
        XCTAssertEqual(store.load().first?.chatConfiguration, binding)
        let encoded = try JSONEncoder().encode(device)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("token"))
        XCTAssertThrowsError(try WebChatConfiguration(serviceURL: "https://secret@chat.example/?token=secret", machineID: "local"))
        let old = try JSONDecoder().decode(MobileDevice.self, from: Data("{\"id\":\"F909464B-03C9-4944-8C53-088D7A571112\",\"name\":\"Old\"}".utf8))
        XCTAssertNil(old.chatConfiguration)
    }
    func testAuthenticatedConversationUsesExactMembershipAndPreservesUnknownContent() async throws {
        let session = fixtureSession { request in
            if request.url?.path == "/api/machines" {
                return (200, [:], Self.machineJSON)
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-only")
            XCTAssertEqual(request.url?.query, "pane_id=pane-a")
            return (200, ["ETag": "\"v1\""], Data("""
            {"source":"claude-transcript","history_id":"history-a","cursor":"older","metadata":{"model":"fixture-model","reasoning_effort":"high"},"turns":[{"role":"assistant","ts":"2026-01-01T00:00:00Z","parts":[{"kind":"text","text":"Visible answer","phase":"final_answer"},{"kind":"future-part","text":"Readable future content"}]}]}
            """.utf8))
        }
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local"), credential: .token("fixture-only"), session: session)
        let result = try await service.conversation(for: Self.target)
        XCTAssertEqual(result.conversation.historyID, "history-a")
        XCTAssertEqual(result.conversation.metadata?.model, "fixture-model")
        XCTAssertEqual(result.conversation.turns.count, 1)
        XCTAssertEqual(result.conversation.turns.first?.parts.last, .unknown(kind: "future-part", description: "Readable future content"))
    }

    private static let target = WebChatTarget(nativeDeviceID: UUID(), presentationID: UUID(), spaceID: "space-a", tabID: "tab-a", paneID: "pane-a")
    private static let machineJSON = Data("""
    {"machines":[{"id":"local","name":"Fixture Linux","kind":"local","enabled":true,"state":"connected","error":null,"snapshot":{"protocol":22,"workspaces":[{"workspace_id":"space-a"}],"tabs":[{"tab_id":"tab-a","workspace_id":"space-a"}],"panes":[{"pane_id":"pane-a","tab_id":"tab-a","workspace_id":"space-a"}]}}]}
    """.utf8)
    private func fixtureSession(_ handler: @escaping (URLRequest) throws -> (Int, [String:String], Data)) -> URLSession {
        WebChatHTTPFixture.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WebChatHTTPFixture.self]
        return URLSession(configuration: configuration)
    }

}


/// External HTTP boundary only: product service parsing/auth/identity/cache remain real.
private final class WebChatHTTPFixture: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, [String:String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "chat.example" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
