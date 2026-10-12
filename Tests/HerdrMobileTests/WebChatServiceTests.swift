import XCTest
import Network
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

    func testCredentialIsScopedToProfileServiceAndBindingGeneration() throws {
        let first = try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local")
        let second = try WebChatConfiguration(serviceURL: "https://other.example/", machineID: "local", credentialID: first.credentialID)
        let deviceID = UUID()
        defer { try? WebChatSecretStore.removeCredential(for: first, nativeDeviceID: deviceID) }
        try WebChatSecretStore.setCredential(.token("fixture-keychain-only"), for: first, nativeDeviceID: deviceID)
        XCTAssertEqual(WebChatSecretStore.credential(for: first, nativeDeviceID: deviceID), .token("fixture-keychain-only"))
        XCTAssertNil(WebChatSecretStore.credential(for: first, nativeDeviceID: UUID()))
        XCTAssertNil(WebChatSecretStore.credential(for: second, nativeDeviceID: deviceID))
        XCTAssertNil(WebChatSecretStore.credential(for: try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local"), nativeDeviceID: deviceID))
    }

    func testUploadChecksBindingAndReturnsOnlyConfirmedRemotePath() async throws {
        let session = fixtureSession { request in
            if request.url?.path == "/api/machines" { return (200, [:], Self.machineJSON) }
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/pane/image")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Herdr-Machine"), "1")
            return (200, [:], Data("{\"ok\":true,\"path\":\"/workspace/.herdr-web-ui/notes.txt\"}".utf8))
        }
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local"), credential: .token("fixture-only"), session: session)
        let uploaded = try await service.upload(for: Self.target, data: Data("safe fixture".utf8), contentType: "text/plain", name: "notes.txt")
        XCTAssertEqual(uploaded.path, "/workspace/.herdr-web-ui/notes.txt")
        do {
            _ = try await service.upload(for: Self.target, data: Data(repeating: 0, count: 8 * 1024 * 1024 + 1), contentType: "text/plain", name: "large.txt")
            XCTFail("Oversized attachment must not upload")
        } catch { XCTAssertEqual(error as? WebChatError, .attachmentTooLarge) }
    }

    func testPairingAcceptsOnlyTheDedicatedServiceCookie() async throws {
        let session = fixtureSession { request in
            XCTAssertEqual(request.url?.path, "/api/devices/pair")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return (204, ["Set-Cookie": "herdr_web_device=fixture-paired; Path=/; HttpOnly; Secure; SameSite=Strict"], Data())
        }
        let binding = try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local")
        let credential = try await WebChatService.pairedCredential(configuration: binding, code: "123456", label: "Fixture iPhone", session: session)
        XCTAssertEqual(credential, .pairedDevice("fixture-paired"))
    }

    func testLoadedOlderImageRemainsAuthorizedAfterPageCachePressureButNotHistoryReplacement() async throws {
        var history = "history-a"
        let session = fixtureSession { request in
            if request.url?.path == "/api/machines" { return (200, [:], Self.machineJSON) }
            if request.url?.path == "/api/pane/conversation/image" {
                return (200, ["Content-Type": "image/png"], Data([137, 80, 78, 71]))
            }
            let first = request.url?.query?.contains("before=first") == true
            let turns = first ? "[{\"role\":\"user\",\"ts\":null,\"parts\":[{\"kind\":\"image\",\"media_type\":\"image/png\",\"ref\":\"older-image\"}]}]" : "[]"
            return (200, [:], Data("{\"source\":\"claude-transcript\",\"history_id\":\"\(history)\",\"turns\":\(turns)}".utf8))
        }
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local"), credential: .token("fixture-only"), session: session)
        _ = try await service.conversation(for: Self.target)
        _ = try await service.conversation(for: Self.target, page: .before("first"))
        for index in 0..<35 { _ = try await service.conversation(for: Self.target, page: .before("page-\(index)")) }
        let image = try await service.image(for: Self.target, ref: "older-image", historyID: "history-a")
        XCTAssertEqual(image.data, Data([137, 80, 78, 71]))
        do { _ = try await service.image(for: Self.target, ref: "arbitrary", historyID: "history-a"); XCTFail("Unknown ref must not load") }
        catch { XCTAssertEqual(error as? WebChatError, .targetMismatch) }
        history = "history-b"
        do { _ = try await service.image(for: Self.target, ref: "older-image", historyID: "history-a"); XCTFail("Old history ref must not load") }
        catch { XCTAssertEqual(error as? WebChatError, .historyChanged) }
    }

    func testImageAndToolOutputStayInsideValidatedCurrentHistory() async throws {
        let session = fixtureSession { request in
            switch request.url?.path {
            case "/api/machines": return (200, [:], Self.machineJSON)
            case "/api/pane/conversation": return (200, [:], Data("""
            {"source":"claude-transcript","history_id":"history-a","turns":[{"role":"assistant","ts":null,"parts":[{"kind":"image","media_type":"image/png","ref":"image-a"},{"kind":"tool","name":"Read","summary":"Read fixture","input":"","output":"short","output_ref":"tool-a"}]}]}
            """.utf8))
            case "/api/pane/conversation/image": return (200, ["Content-Type":"image/png"], Data([137,80,78,71]))
            case "/api/pane/conversation/tool-output": return (200, ["Content-Type":"text/plain"], Data("complete fixture output".utf8))
            default: throw WebChatError.invalidResponse
            }
        }
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local"), credential: .token("fixture-only"), session: session)
        _ = try await service.conversation(for: Self.target)
        let image = try await service.image(for: Self.target, ref: "image-a", historyID: "history-a")
        XCTAssertEqual(image.contentType, "image/png")
        XCTAssertEqual(image.data, Data([137,80,78,71]))
        let output = try await service.toolOutput(for: Self.target, ref: "tool-a", historyID: "history-a")
        XCTAssertEqual(output, "complete fixture output")
        do {
            _ = try await service.image(for: Self.target, ref: "image-a", historyID: "replaced-history")
            XCTFail("A stale history reference must be rejected")
        } catch { XCTAssertEqual(error as? WebChatError, .historyChanged) }
    }

    func testLateOlderPageCannotReplaceNewHistory() async throws {
        let olderRequested = expectation(description: "Old page held at HTTP boundary")
        var latestCount = 0
        let session = fixtureSession { request in
            if request.url?.path == "/api/machines" { return (200, [:], Self.machineJSON) }
            let older = request.url?.query?.contains("before=") == true
            if !older { latestCount += 1 }
            let history = older || latestCount == 1 ? "old-history" : "new-history"
            return (200, ["ETag": history], Data("{\"source\":\"claude-transcript\",\"history_id\":\"\(history)\",\"turns\":[]}".utf8))
        }
        WebChatHTTPFixture.shouldHold = { $0.url?.query?.contains("before=") == true }
        WebChatHTTPFixture.onHeld = { olderRequested.fulfill() }
        defer { WebChatHTTPFixture.shouldHold = nil; WebChatHTTPFixture.onHeld = nil; WebChatHTTPFixture.release() }
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local"), credential: .token("fixture-only"), session: session)
        _ = try await service.conversation(for: Self.target)
        let older = Task { try await service.conversation(for: Self.target, page: .before("older")) }
        await fulfillment(of: [olderRequested], timeout: 2)
        let latest = try await service.conversation(for: Self.target)
        XCTAssertTrue(latest.historyReplaced)
        WebChatHTTPFixture.release()
        do { _ = try await older.value; XCTFail("A late page must not revert new history") }
        catch { XCTAssertEqual(error as? WebChatError, .historyChanged) }
    }

    @MainActor
    func testFailedSettingsSaveRestoresTheOriginalCredential() async throws {
        let binding = try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local")
        let device = MobileDevice(name: "Linux", host: "linux.example", username: "developer", chatConfiguration: binding)
        defer { try? WebChatSecretStore.removeCredential(for: binding, nativeDeviceID: device.id) }
        try WebChatSecretStore.setCredential(.token("original-fixture"), for: binding, nativeDeviceID: device.id)
        let model = WebChatSettingsModel(device: device, session: fixtureSession { _ in (200, [:], Self.machineJSON) })
        model.token = "replacement-fixture"
        try await model.signIn()
        XCTAssertThrowsError(try model.save(using: { _ in throw WebChatError.invalidConfiguration }))
        XCTAssertEqual(WebChatSecretStore.credential(for: binding, nativeDeviceID: device.id), .token("original-fixture"))
        let saved = try model.save(using: { _ in })
        XCTAssertEqual(saved.credentialID, binding.credentialID)
        XCTAssertEqual(WebChatSecretStore.credential(for: binding, nativeDeviceID: device.id), .token("replacement-fixture"))
    }

    func testCursorGapPagingUsesExactBeforeAndSinceWithoutTimestampGuessing() async throws {
        let session = fixtureSession { request in
            if request.url?.path == "/api/machines" { return (200, [:], Self.machineJSON) }
            if request.url?.query?.contains("before=") == true {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
                XCTAssertEqual(query?.first { $0.name == "before" }?.value, "cursor-new")
                XCTAssertEqual(query?.first { $0.name == "since" }?.value, "cursor-old")
            }
            return (200, [:], Data("{\"source\":\"claude-transcript\",\"history_id\":\"history-a\",\"cursor\":\"cursor-new\",\"turns\":[]}".utf8))
        }
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local"), credential: .token("fixture-only"), session: session)
        _ = try await service.conversation(for: Self.target)
        let page = try await service.conversation(for: Self.target, page: .between(before: "cursor-new", since: "cursor-old"))
        XCTAssertEqual(page.conversation.historyID, "history-a")
    }

    func testBrowsingManyPagesReleasesOlderAnswersButKeepsLatestValidation() async throws {
        let session = fixtureSession { request in
            if request.url?.path == "/api/machines" { return (200, [:], Self.machineJSON) }
            if request.value(forHTTPHeaderField: "If-None-Match") != nil { return (304, [:], Data()) }
            return (200, ["ETag":"fixture-version"], Data("{\"source\":\"claude-transcript\",\"history_id\":\"history-a\",\"turns\":[]}".utf8))
        }
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local"), credential: .token("fixture-only"), session: session)
        _ = try await service.conversation(for: Self.target)
        for index in 0..<35 { _ = try await service.conversation(for: Self.target, page: .before("older-\(index)")) }
        let latest = try await service.conversation(for: Self.target)
        XCTAssertTrue(latest.notModified)
        let old = try await service.conversation(for: Self.target, page: .before("older-0"))
        XCTAssertFalse(old.notModified, "Discarded pages must be revalidated without retaining their old cached body")
    }

    func testAnOversizedHTTPBodyIsRejectedBeforeAllocatingItsDeclaredSize() async throws {
        let session = fixtureSession { _ in (200, ["Content-Length":"999999999"], Self.machineJSON) }
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local"), credential: .token("fixture-only"), session: session)
        do { _ = try await service.machines(); XCTFail("A declared oversized body must be refused") }
        catch { XCTAssertEqual(error as? WebChatError, .invalidResponse) }
    }

    func testBytePressureReleasesLargeOlderPagesWithoutLosingLatestHistoryProof() async throws {
        let text = String(repeating: "x", count: 5 * 1024 * 1024)
        let response = Data("{\"source\":\"claude-transcript\",\"history_id\":\"history-a\",\"turns\":[{\"role\":\"assistant\",\"ts\":null,\"parts\":[{\"kind\":\"text\",\"text\":\"\(text)\"}]}]}".utf8)
        let session = fixtureSession { request in
            if request.url?.path == "/api/machines" { return (200, [:], Self.machineJSON) }
            return request.value(forHTTPHeaderField: "If-None-Match") != nil ? (304, [:], Data()) : (200, ["ETag":"large-fixture"], response)
        }
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local"), credential: .token("fixture-only"), session: session)
        _ = try await service.conversation(for: Self.target)
        _ = try await service.conversation(for: Self.target, page: .before("large-older"))
        let latest = try await service.conversation(for: Self.target)
        XCTAssertTrue(latest.notModified, "Latest history proof remains useful under cache pressure")
        let older = try await service.conversation(for: Self.target, page: .before("large-older"))
        XCTAssertFalse(older.notModified, "Large old pages are released instead of evicting current history proof")
    }

    func testConfiguredMachineUsesExactRemoteRouteAndNeverFallsBackToLocal() async throws {
        var mismatch = false
        let remoteMachines = String(decoding: Self.machineJSON, as: UTF8.self)
            .replacingOccurrences(of: "\"local\"", with: "\"remote-a\"")
            .replacingOccurrences(of: "\"protocol\":22", with: "\"protocol\":23")
        let session = fixtureSession { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-only")
            if request.url?.path == "/proxy/api/machines" {
                let snapshot = mismatch ? remoteMachines.replacingOccurrences(of: "space-a", with: "different-space") : remoteMachines
                return (200, [:], Data(snapshot.utf8))
            }
            XCTAssertFalse(mismatch, "Target mismatch must prevent a pane request")
            XCTAssertEqual(request.url?.path, "/proxy/api/machines/remote-a/pane/conversation")
            return (200, [:], Data("{\"source\":\"claude-transcript\",\"history_id\":\"history-a\",\"turns\":[]}".utf8))
        }
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "https://chat.example/proxy/", machineID: "remote-a"), credential: .token("fixture-only"), session: session)
        let answer = try await service.conversation(for: Self.target)
        XCTAssertEqual(answer.conversation.historyID, "history-a")
        mismatch = true
        do { _ = try await service.conversation(for: Self.target); XCTFail("Same pane ID in another Space must not be accepted") }
        catch { XCTAssertEqual(error as? WebChatError, .targetMismatch) }
    }

    func testAuthenticationErrorsNeverPresentReflectedCredentials() async throws {
        let session = fixtureSession { _ in (401, [:], Data("Reflected fixture-secret-value".utf8)) }
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local"), credential: .token("fixture-secret-value"), session: session)
        do { _ = try await service.machines(); XCTFail("Unauthorized service must require sign-in") }
        catch {
            XCTAssertEqual(error as? WebChatError, .unauthorized)
            XCTAssertFalse(error.localizedDescription.contains("fixture-secret-value"))
            XCTAssertFalse(error.localizedDescription.contains("Reflected"))
        }
    }

    func testInvalidationRejectsAnInflightAnswerAndClearsItsETag() async throws {
        let held = expectation(description: "Response held at the HTTP boundary")
        let session = fixtureSession { request in
            if request.url?.path == "/api/machines" { return (200, [:], Self.machineJSON) }
            XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
            return (200, ["ETag":"fixture-version"], Data("{\"source\":\"claude-transcript\",\"history_id\":\"history-a\",\"turns\":[]}".utf8))
        }
        WebChatHTTPFixture.shouldHold = { $0.url?.path == "/api/pane/conversation" }
        WebChatHTTPFixture.onHeld = { held.fulfill() }
        defer { WebChatHTTPFixture.shouldHold = nil; WebChatHTTPFixture.onHeld = nil; WebChatHTTPFixture.release() }
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local"), credential: .token("fixture-only"), session: session)
        let waiting = Task { try await service.conversation(for: Self.target) }
        await fulfillment(of: [held], timeout: 2)
        await service.invalidate()
        WebChatHTTPFixture.release()
        do { _ = try await waiting.value; XCTFail("An invalidated response must not be published") }
        catch { XCTAssertEqual(error as? WebChatError, .staleResponse) }
        WebChatHTTPFixture.shouldHold = nil
        WebChatHTTPFixture.onHeld = nil
        let current = try await service.conversation(for: Self.target)
        XCTAssertFalse(current.notModified)
    }

    func testHistoryConflictRequiresFreshLatestWithoutOldETag() async throws {
        var conversationCount = 0
        let session = fixtureSession { request in
            if request.url?.path == "/api/machines" { return (200, [:], Self.machineJSON) }
            conversationCount += 1
            if conversationCount == 2 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "old-version")
                return (409, [:], Data("{\"error\":\"history_changed\"}".utf8))
            }
            XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
            let history = conversationCount == 1 ? "old-history" : "new-history"
            return (200, ["ETag":"old-version"], Data("{\"source\":\"claude-transcript\",\"history_id\":\"\(history)\",\"turns\":[]}".utf8))
        }
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "https://chat.example/", machineID: "local"), credential: .token("fixture-only"), session: session)
        _ = try await service.conversation(for: Self.target)
        do { _ = try await service.conversation(for: Self.target); XCTFail("A replaced history must be surfaced") }
        catch { XCTAssertEqual(error as? WebChatError, .historyChanged) }
        let current = try await service.conversation(for: Self.target)
        XCTAssertEqual(current.conversation.historyID, "new-history")
    }

    func testProductionSessionRefusesRedirectBeforeForwardingCredentials() async throws {
        let destinationReached = expectation(description: "Redirect destination must never be contacted")
        destinationReached.isInverted = true
        let destinationReady = expectation(description: "Redirect destination listening")
        let destination = try WebChatLoopbackServer(response: "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", ready: { destinationReady.fulfill() }, request: { _ in destinationReached.fulfill() })
        defer { destination.stop() }
        await fulfillment(of: [destinationReady], timeout: 2)
        let destinationPort = try XCTUnwrap(destination.port)
        let originReady = expectation(description: "Redirect origin listening")
        let origin = try WebChatLoopbackServer(response: "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:\(destinationPort)/other\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", ready: { originReady.fulfill() }, request: { request in
            XCTAssertTrue(request.contains("Authorization: Bearer fixture-redirect-only"))
        })
        defer { origin.stop() }
        await fulfillment(of: [originReady], timeout: 2)
        let originPort = try XCTUnwrap(origin.port)
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "http://127.0.0.1:\(originPort)/", machineID: "local"), credential: .token("fixture-redirect-only"))
        do { _ = try await service.machines(); XCTFail("The real URLSession must refuse redirects") }
        catch { XCTAssertEqual(error as? WebChatError, .unsafeRedirect) }
        await fulfillment(of: [destinationReached], timeout: 0.3)
    }

    func testNativeHTTPRestrictionPresentsAnActionableHTTPSInstruction() async throws {
        let session = fixtureSession { _ in throw URLError(.appTransportSecurityRequiresSecureConnection) }
        let service = WebChatService(configuration: try WebChatConfiguration(serviceURL: "http://chat.example/", machineID: "local"), credential: .token("fixture-only"), session: session)
        do { _ = try await service.machines(); XCTFail("Native HTTP restrictions must be surfaced") }
        catch { XCTAssertEqual(error as? WebChatError, .httpRestricted) }
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
    static var shouldHold: ((URLRequest) -> Bool)?
    static var onHeld: (() -> Void)?
    private static var held: (() -> Void)?
    private static let replyLock = NSLock()
    private var stopped = false
    private let stateLock = NSLock()
    static func release() {
        replyLock.lock(); let reply = held; held = nil; replyLock.unlock()
        reply?()
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "chat.example" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            let reply = { [self] in
                stateLock.lock(); let active = !stopped; stateLock.unlock()
                guard active else { return }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
            if Self.shouldHold?(request) == true {
                Self.replyLock.lock(); Self.held = reply; Self.replyLock.unlock()
                Self.onHeld?()
            } else { reply() }
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { stateLock.lock(); stopped = true; stateLock.unlock() }
}

/// Real URLSession boundary for redirect protection. Binds only loopback, uses fixture secrets.
private final class WebChatLoopbackServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "herdr.chat.redirect.fixture")
    var port: UInt16? { listener.port?.rawValue }

    init(response: String, ready: @escaping () -> Void, request: @escaping (String) -> Void) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { state in if case .ready = state { ready() } }
        listener.newConnectionHandler = { [queue] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, _, _ in
                if let data { request(String(decoding: data, as: UTF8.self)) }
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
    }
    func stop() { listener.cancel() }
}
