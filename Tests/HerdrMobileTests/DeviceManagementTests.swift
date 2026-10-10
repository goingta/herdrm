import XCTest
import HerdrKit
import HerdrSSH
@testable import HerdrMobile

@MainActor
final class DeviceManagementTests: XCTestCase {
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
