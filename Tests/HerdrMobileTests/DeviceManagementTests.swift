import XCTest
import HerdrKit
import HerdrSSH
@testable import HerdrMobile

@MainActor
final class DeviceManagementTests: XCTestCase {
    func testReturningToHealthyConnectionKeepsTransportAndSnapshot() async throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.save([MobileDevice(name: "Daily", host: "host.example", username: "alice")])
        let remote = FixtureTransport(label: "Current workspace")
        let model = MobileAppModel(store: store, connector: { _ in remote })
        model.connectSelected()
        try await eventually { model.spaces.first?.label == "Current workspace" }
        let session = try XCTUnwrap(model.selectedSession)
        let identity = session.connectionID
        model.connectSelected()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(session.connectionID, identity, "A healthy foreground return must not replace the SSH session")
        let closed = await remote.isClosed
        XCTAssertFalse(closed, "Validation must retain the current remote transport")
        XCTAssertEqual(model.spaces.first?.label, "Current workspace")
        await session.disconnect()
    }

    func testConnectionEditClearsOldHostUnreadWhileNameOnlyEditPreservesIt() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = MobileDeviceStore(defaults: defaults)
        let device = MobileDevice(name: "Daily", host: "old.example", username: "alice")
        store.save([device])
        let unread = AgentReadState(defaults: defaults)
        let model = MobileAppModel(store: store, readState: unread)
        func agent(_ status: String) throws -> AgentInfo {
            try JSONDecoder().decode(AgentInfo.self, from: Data("{\"workspace_id\":\"s\",\"tab_id\":\"t\",\"pane_id\":\"same-pane\",\"agent\":\"codex\",\"agent_status\":\"\(status)\"}".utf8))
        }
        unread.apply(agents: [try agent("working")], deviceID: device.id)
        unread.apply(agents: [try agent("done")], deviceID: device.id)
        let key = AgentUnreadKey(deviceID: device.id, paneID: "same-pane")
        XCTAssertTrue(unread.unread.contains(key))
        var edited = device
        edited.name = "New display name"
        try model.updateDevice(edited)
        XCTAssertTrue(unread.unread.contains(key), "A name edit keeps completion reminders")
        // Avoid opening a network connection: this public operation allows no active device.
        model.selectedDeviceID = nil
        edited.host = "new.example"
        try model.updateDevice(edited)
        XCTAssertFalse(unread.unread.contains(key), "Reused remote pane IDs on a new host cannot inherit the old host's unread result")
        XCTAssertFalse(AgentReadState(defaults: defaults).unread.contains(key))
    }

    func testForegroundValidationDeadlineReplacesUnresponsiveTransportAndRejectsItsLateReply() async throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let device = MobileDevice(name: "Daily", host: "host.example", username: "alice")
        store.save([device])
        let first = FixtureTransport(label: "Prior snapshot")
        let next = FixtureTransport(label: "Recovered snapshot")
        let gate = RemoteReplyGate()
        let boundary = ForegroundConnector(first: first, next: next)
        let model = MobileAppModel(store: store, connector: { _ in await boundary.open() })
        model.connectSelected()
        try await eventually { model.spaces.first?.label == "Prior snapshot" }
        model.selectedSpaceID = "Prior snapshot"
        let priorID = model.selectedSession?.connectionID
        await first.holdSnapshot(using: gate)
        model.suspendSelected()
        model.resumeSelected(validationTimeout: .milliseconds(80))
        try await eventually { await gate.isWaiting }
        XCTAssertFalse(model.selectedTransportReady)
        XCTAssertEqual(model.spaces.first?.label, "Prior snapshot", "Recovery keeps the previous context")
        try await eventually { model.spaces.first?.label == "Recovered snapshot" }
        XCTAssertNotEqual(model.selectedSession?.connectionID, priorID)
        await gate.release()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(model.spaces.first?.label, "Recovered snapshot", "Late prior-generation snapshot cannot replace the new transport's data")
        XCTAssertTrue(model.selectedTransportReady)
        await model.selectedSession?.disconnect()
    }

    func testRapidReturnToDeviceWaitsForItsSharedBridgeTeardown() async throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let first = MobileDevice(kind: .tailcat, name: "Bridge device")
        let second = MobileDevice(name: "SSH device", host: "host.example", username: "alice")
        store.save([first, second])
        let bridge = SharedBridgeFixture()
        let model = MobileAppModel(store: store, connector: { device in
            if device.id == first.id { return await bridge.open() }
            return FixtureTransport(label: "Other workspace")
        })
        model.connectSelected()
        try await eventually { model.spaces.first?.label == "Bridge workspace" }
        model.selectDevice(second.id)
        model.selectDevice(first.id)
        try await eventually { await bridge.wasClosed }
        try await eventually { model.spaces.first?.label == "Bridge workspace" }
        let refreshed = await model.selectedSession?.refresh()
        XCTAssertEqual(refreshed, true, "Old bridge teardown must not kill the replacement connection")
        await model.selectedSession?.disconnect()
    }

    func testPreviousHostSnapshotCannotReplaceCurrentDeviceData() async throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let first = MobileDevice(name: "First", host: "first.example", username: "alice")
        let second = MobileDevice(name: "Second", host: "second.example", username: "bob")
        store.save([first, second])
        let replyGate = RemoteReplyGate()
        let firstTransport = FixtureTransport(label: "Obsolete snapshot")
        let secondTransport = FixtureTransport(label: "Current snapshot")
        let model = MobileAppModel(store: store, connector: { device in
            device.id == first.id ? firstTransport : secondTransport
        })
        model.connectSelected()
        try await eventually { model.spaces.first?.label == "Obsolete snapshot" }
        let firstSession = try XCTUnwrap(model.selectedSession)
        await firstTransport.holdSnapshot(using: replyGate)
        let pendingRefresh = Task { await firstSession.refresh() }
        try await eventually { await replyGate.isWaiting }
        model.selectDevice(second.id)
        try await eventually { model.spaces.first?.label == "Current snapshot" }
        await replyGate.release()
        _ = await pendingRefresh.value
        try await eventually { await firstTransport.isClosed }
        XCTAssertEqual(model.spaces.map(\.label), ["Current snapshot"])
        XCTAssertNil(model.session(for: first.id)?.snapshot)
        await model.selectedSession?.disconnect()
    }

    func testInvalidEditLeavesSavedConfigurationUnchanged() throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let original = MobileDevice(name: "Daily", host: "host.example", username: "alice")
        store.save([original])
        let model = MobileAppModel(store: store)
        var invalid = original
        invalid.host = " \n "
        XCTAssertThrowsError(try model.updateDevice(invalid))
        invalid = original
        invalid.username = "\n "
        XCTAssertThrowsError(try model.updateDevice(invalid))
        invalid = original
        invalid.port = 0
        XCTAssertThrowsError(try model.updateDevice(invalid))
        XCTAssertEqual(model.selectedDevice, original)
        XCTAssertEqual(MobileAppModel(store: store).devices, [original])
    }

    func testExistingVersionOnePasswordConfigurationStillLoads() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let legacy = """
        {"version":1,"devices":[{"id":"F909464B-03C9-4944-8C53-088D7A571112","name":"Legacy","host":"legacy.example","port":2222,"username":"alice","authMethod":"password","socketPath":"/run/herdr.sock"}]}
        """
        defaults.set(Data(legacy.utf8), forKey: "devices.v1")
        let model = MobileAppModel(store: MobileDeviceStore(defaults: defaults))
        XCTAssertEqual(model.devices.count, 1)
        XCTAssertEqual(model.selectedDevice?.host, "legacy.example")
        XCTAssertEqual(model.selectedDevice?.port, 2222)
        XCTAssertEqual(model.selectedDevice?.authMethod, .password)
        XCTAssertEqual(model.selectedDevice?.socketPath, "/run/herdr.sock")
    }

    func testRenamingDeviceKeepsCurrentAgentAndConnection() async throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let device = MobileDevice(name: "Original", host: "host.example", username: "alice")
        store.save([device])
        let transport = FixtureTransport(label: "Workspace")
        let model = MobileAppModel(store: store, connector: { _ in transport })
        model.connectSelected()
        try await eventually { model.spaces.first?.label == "Workspace" }
        model.selectedSpaceID = "Workspace"
        model.selectedAgentPaneID = "existing-pane"
        var renamed = device
        renamed.name = "Daily development"
        try model.updateDevice(renamed)
        XCTAssertEqual(model.selectedDevice?.name, "Daily development")
        XCTAssertEqual(model.selectedConnectionState, .connected(version: "fixture"))
        XCTAssertEqual(model.selectedSpaceID, "Workspace")
        XCTAssertEqual(model.selectedAgentPaneID, "existing-pane")
        await model.selectedSession?.disconnect()
    }

    func testDeletingDeviceKeepsOtherCredentialsSharedTrustAndPhoneIdentity() async throws {
        let store = MobileDeviceStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let host = "\(UUID().uuidString).example"
        let first = MobileDevice(name: "First", host: host, username: "alice", authMethod: .password)
        let second = MobileDevice(name: "Second", host: host, username: "bob", authMethod: .password)
        try MobileSecretStore.setPassword("first-password", for: first.id)
        try MobileSecretStore.setPassword("second-password", for: second.id)
        KnownHostsStore.pin(host: host, port: 22, algorithm: "ssh-ed25519", fingerprint: "trusted-host")
        defer {
            try? MobileSecretStore.removePassword(for: first.id)
            try? MobileSecretStore.removePassword(for: second.id)
            KnownHostsStore.unpin(host: host, port: 22)
        }
        let phoneIdentity = DeviceKey.authorizedKeysLine(DeviceKey.ensure())
        store.save([first, second])
        let firstTransport = FixtureTransport(label: "First workspace")
        let secondTransport = FixtureTransport(label: "Second workspace")
        let model = MobileAppModel(store: store, connector: { device in
            device.id == first.id ? firstTransport : secondTransport
        })
        model.connectSelected()
        try await eventually { model.spaces.first?.label == "First workspace" }
        try model.removeDevice(first)
        try await eventually { await firstTransport.isClosed }
        XCTAssertEqual(MobileAppModel(store: store).devices, [second])
        XCTAssertEqual(model.selectedDeviceID, second.id)
        XCTAssertNil(MobileSecretStore.password(for: first.id))
        XCTAssertEqual(MobileSecretStore.password(for: second.id), "second-password")
        XCTAssertEqual(KnownHostsStore.fingerprint(host: host, port: 22, algorithm: "ssh-ed25519"), "trusted-host")
        XCTAssertEqual(DeviceKey.authorizedKeysLine(DeviceKey.ensure()), phoneIdentity)
        await model.selectedSession?.disconnect()
    }

    func testEditingHostKeepsIdentityAndPasswordButDiscardsOldConnection() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = MobileDeviceStore(defaults: defaults)
        let original = MobileDevice(name: "Original", host: "old.example", username: "alice", authMethod: .password)
        try MobileSecretStore.setPassword("original-password", for: original.id)
        defer { try? MobileSecretStore.removePassword(for: original.id) }
        store.save([original])
        let gate = ConnectionGate()
        let model = MobileAppModel(store: store, connector: { try await gate.open($0) })
        model.connectSelected()
        try await gate.waitForArrival(original.host)
        var edited = original
        edited.name = "New environment"
        edited.host = "new.example"
        edited.port = 2222
        edited.username = "bob"
        edited.socketPath = "/run/user/1000/herdr.sock"
        try model.updateDevice(edited)
        XCTAssertEqual(model.selectedDevice, edited)
        XCTAssertEqual(MobileAppModel(store: store).devices, [edited])
        XCTAssertEqual(MobileSecretStore.password(for: edited.id), "original-password")
        guard model.selectedDevice == edited else { throw CancellationError() }
        try await gate.waitForArrival(edited.host)
        let latest = FixtureTransport(label: "Edited workspace")
        await gate.resolve(edited.host, with: latest)
        try await eventually { model.spaces.first?.label == "Edited workspace" }
        let obsolete = FixtureTransport(label: "Obsolete workspace")
        await gate.resolve(original.host, with: obsolete)
        try await eventually { await obsolete.isClosed }
        XCTAssertEqual(model.spaces.map(\.label), ["Edited workspace"])
        await model.selectedSession?.disconnect()
    }

    func testSwitchingDeviceRejectsDelayedConnectionFromPreviousHost() async throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = MobileDeviceStore(defaults: defaults)
        let first = MobileDevice(name: "First", host: "first.example", username: "alice")
        let second = MobileDevice(name: "Second", host: "second.example", username: "bob")
        store.save([first, second])
        let gate = ConnectionGate()
        let model = MobileAppModel(store: store, connector: { try await gate.open($0) })
        model.connectSelected()
        try await gate.waitForArrival(first.host)
        model.selectDevice(second.id)
        try await gate.waitForArrival(second.host)
        let secondTransport = FixtureTransport(label: "Second workspace")
        await gate.resolve(second.host, with: secondTransport)
        try await eventually { model.spaces.first?.label == "Second workspace" }
        let lateTransport = FixtureTransport(label: "First workspace")
        await gate.resolve(first.host, with: lateTransport)
        try await eventually { await lateTransport.isClosed }
        XCTAssertEqual(model.selectedDeviceID, second.id)
        XCTAssertEqual(model.spaces.map(\.label), ["Second workspace"])
        XCTAssertEqual(model.session(for: first.id)?.state, .idle)
        await model.selectedSession?.disconnect()
    }
}

/// The remote boundary can ignore cancellation and finish after the user switches.
private actor ConnectionGate {
    private var pending: [String: CheckedContinuation<MobileTransport, Error>] = [:]

    func open(_ device: MobileDevice) async throws -> MobileTransport {
        try await withCheckedThrowingContinuation { continuation in
            pending[device.host] = continuation
        }
    }

    func waitForArrival(_ host: String) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while pending[host] == nil {
            guard ContinuousClock.now < deadline else { throw FixtureError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func resolve(_ id: String, with transport: MobileTransport) {
        pending.removeValue(forKey: id)?.resume(returning: transport)
    }
}

private actor FixtureTransport: MobileTransport {
    let label: String
    private var snapshotGate: RemoteReplyGate?
    private(set) var isClosed = false
    init(label: String, snapshotGate: RemoteReplyGate? = nil) {
        self.label = label
        self.snapshotGate = snapshotGate
    }

    func holdSnapshot(using gate: RemoteReplyGate) { snapshotGate = gate }

    func request(method: String, params: JSONValue) async throws -> JSONValue {
        if method == "ping" { return .object(["version": .string("fixture"), "protocol": .number(22)]) }
        await snapshotGate?.wait()
        return .object(["snapshot": .object([
            "agents": .array([]),
            "workspaces": .array([.object([
                "workspace_id": .string(label), "number": .number(1), "label": .string(label),
            ])]),
        ])])
    }

    nonisolated func events(kinds: [String], statusPaneIDs: [String]) -> AsyncThrowingStream<HerdrEvent, Error> {
        AsyncThrowingStream { _ in }
    }

    func openTerminal(command: String, columns: Int, rows: Int) async throws -> SSHPTYChannel {
        throw CancellationError()
    }
    func close() async { isClosed = true }
}

private enum FixtureError: Error { case timeout }

/// Simulates Tailcat's process-global resource reused by successive transports.
private actor SharedBridgeFixture {
    private var isAlive = false
    private(set) var wasClosed = false

    func open() -> MobileTransport {
        isAlive = true
        return SharedBridgeTransport(bridge: self)
    }

    func checkAvailable() throws {
        guard isAlive else { throw FixtureError.timeout }
    }

    func close() async {
        try? await Task.sleep(for: .milliseconds(100))
        isAlive = false
        wasClosed = true
    }
}

private actor SharedBridgeTransport: MobileTransport {
    let bridge: SharedBridgeFixture
    let replies = FixtureTransport(label: "Bridge workspace")
    init(bridge: SharedBridgeFixture) { self.bridge = bridge }

    func request(method: String, params: JSONValue) async throws -> JSONValue {
        try await bridge.checkAvailable()
        return try await replies.request(method: method, params: params)
    }

    nonisolated func events(kinds: [String], statusPaneIDs: [String]) -> AsyncThrowingStream<HerdrEvent, Error> {
        AsyncThrowingStream { _ in }
    }
    func openTerminal(command: String, columns: Int, rows: Int) async throws -> SSHPTYChannel {
        throw CancellationError()
    }
    func close() async { await bridge.close() }
}

private actor RemoteReplyGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    func wait() async {
        await withCheckedContinuation {
            isWaiting = true
            continuation = $0
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private func eventually(_ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !(await condition()) {
        if ContinuousClock.now >= deadline {
            XCTFail("Expected state did not arrive within two seconds")
            throw CancellationError()
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}

private actor ForegroundConnector {
    let first: MobileTransport
    let next: MobileTransport
    private var opened = false
    init(first: MobileTransport, next: MobileTransport) { self.first = first; self.next = next }
    func open() -> MobileTransport {
        if !opened { opened = true; return first }
        return next
    }
}
