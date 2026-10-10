import Foundation
import HerdrKit
import SwiftUI

typealias MobileTransportConnector = @Sendable (MobileDevice) async throws -> MobileTransport

/// Connection state for one device, mirroring the Mac app's session states.
enum MobileConnectionState: Equatable {
    case idle
    case connecting
    case connected(version: String)
    case failed(String)
}

/// One device's live herdr view: transport + snapshot + event pump.
@MainActor
final class MobileDeviceSession {
    var device: MobileDevice
    var state: MobileConnectionState = .idle
    var snapshot: SessionSnapshot?
    private(set) var transport: MobileTransport?
    private var eventTask: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?
    private var refreshDebouncePending = false
    private var snapshotRefreshTask: Task<Bool, Never>?
    private var snapshotRefreshToken: UUID?
    private var refreshRequested = false
    private var statusGeneration: UInt64 = 0
    private let connector: MobileTransportConnector
    private var connectToken: UUID?

    var onChange: (() -> Void)?
    var onAgents: (([AgentInfo], Bool) -> Void)?
    var onConnectionLost: (() -> Void)?
    private(set) var connectionID = UUID()

    init(device: MobileDevice, connector: @escaping MobileTransportConnector) {
        self.device = device
        self.connector = connector
    }

    func connect() async {
        guard !Task.isCancelled else { return }
        guard case .connecting = state else {
            let token = UUID()
            connectToken = token
            connectionID = UUID()
            onConnectionLost?()
            state = .connecting
            let oldTransport = self.transport
            self.transport = nil
            eventTask?.cancel()
            onChange?()
            await oldTransport?.close()
            guard connectToken == token, !Task.isCancelled else { return }
            var openingTransport: MobileTransport?
            do {
                let transport = try await connector(device)
                openingTransport = transport
                guard connectToken == token, !Task.isCancelled else {
                    await transport.close()
                    return
                }
                let pong = try await transport.request(
                    method: "ping", params: .object([:]), as: PingResult.self
                )
                guard pong.protocolVersion >= 17 else {
                    throw HerdrError.incompatibleProtocol(pong.protocolVersion)
                }
                guard connectToken == token, !Task.isCancelled else {
                    await transport.close()
                    return
                }
                self.transport = transport
                state = .connected(version: pong.version)
                await refresh()
                if connectToken == token { startEventPump() }
            } catch {
                await openingTransport?.close()
                guard connectToken == token, !Task.isCancelled else { return }
                state = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
            onChange?()
            return
        }
    }

    func disconnect() async {
        let oldTransport = invalidateConnection()
        await oldTransport?.close()
    }

    /// Invalidates before the next actor turn, including a connection still opening.
    @discardableResult
    func cancelConnection() -> Task<Void, Never> {
        let oldTransport = invalidateConnection()
        snapshot = nil
        onChange?()
        return Task { await oldTransport?.close() }
    }

    private func invalidateConnection() -> MobileTransport? {
        onConnectionLost?()
        connectToken = nil
        eventTask?.cancel()
        eventTask = nil
        refreshDebounceTask?.cancel()
        refreshDebounceTask = nil
        refreshDebouncePending = false
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = nil
        snapshotRefreshToken = nil
        refreshRequested = false
        let oldTransport = transport
        transport = nil
        state = .idle
        onChange?()
        return oldTransport
    }

    @discardableResult
    func refresh() async -> Bool {
        refreshRequested = true
        if let task = snapshotRefreshTask {
            return await task.value
        }
        let token = UUID()
        snapshotRefreshToken = token
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            var latestSucceeded = false
            while !Task.isCancelled, self.refreshRequested {
                self.refreshRequested = false
                latestSucceeded = await self.performRefresh()
            }
            if self.snapshotRefreshToken == token {
                self.snapshotRefreshToken = nil
                self.snapshotRefreshTask = nil
            }
            return latestSucceeded
        }
        snapshotRefreshTask = task
        return await task.value
    }

    private func performRefresh() async -> Bool {
        guard let transport else { return false }
        let generation = statusGeneration
        struct Envelope: Codable { let snapshot: SessionSnapshot }
        do {
            let fetched = try await transport.request(
                method: "session.snapshot", as: Envelope.self
            ).snapshot
            guard !Task.isCancelled, self.transport === transport else {
                return false
            }
            guard statusGeneration == generation else {
                refreshRequested = true
                return true
            }
            onAgents?(fetched.agents, true)
            snapshot = fetched
            onChange?()
            return true
        } catch {
            // A failed refresh keeps the last snapshot; the event pump's own
            // failure handling decides when the connection is actually gone.
            return false
        }
    }

    private func startEventPump() {
        guard let transport else { return }
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            do {
                eventSubscriptions: while !Task.isCancelled {
                    guard let self else { return }
                    let subscribedPaneIDs = self.statusSubscriptionPaneIDs
                    let stream = transport.events(
                        kinds: HerdrEvent.allKinds,
                        statusPaneIDs: subscribedPaneIDs
                    )
                    var needsResubscribe = false
                    var resubscribeDelay = Duration.milliseconds(100)
                    for try await event in stream {
                        guard !Task.isCancelled else { return }
                        if event.kind == HerdrEvent.agentStatusChangedKind,
                           self.applyAgentStatusEvent(event) {
                            self.scheduleRefresh()
                        } else if event.kind == HerdrEvent.subscriptionStartedKind
                            || event.kind == HerdrEvent.agentStatusChangedKind
                            || Self.paneTopologyEventKinds.contains(event.kind) {
                            if !(await self.refresh()) {
                                needsResubscribe = true
                                resubscribeDelay = .milliseconds(500)
                                break
                            }
                        } else {
                            self.scheduleRefresh()
                        }

                        if event.kind == HerdrEvent.subscriptionStartedKind
                            || Self.paneTopologyEventKinds.contains(event.kind),
                           self.statusSubscriptionPaneIDs != subscribedPaneIDs {
                            needsResubscribe = true
                            break
                        }
                    }
                    if needsResubscribe {
                        try? await Task.sleep(for: resubscribeDelay)
                        continue eventSubscriptions
                    }
                    guard !Task.isCancelled else { return }
                    throw HerdrError.connectionFailed("event stream ended")
                }
            } catch {}
            // Stream ended: the connection is likely gone. Reflect it so the
            // UI offers Reconnect instead of silently going stale.
            guard let self, !Task.isCancelled else { return }
            if case .connected = self.state {
                self.onConnectionLost?()
                self.state = .failed(AppLocalization.string("Connection lost"))
                self.onChange?()
            }
        }
    }

    /// Coalesces event bursts into one snapshot fetch per 300 ms.
    private func scheduleRefresh() {
        guard refreshDebounceTask == nil else {
            refreshDebouncePending = true
            return
        }
        refreshDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled else { return }
            await self.refresh()
            self.refreshDebounceTask = nil
            if self.refreshDebouncePending {
                self.refreshDebouncePending = false
                self.scheduleRefresh()
            }
        }
    }

    private var statusSubscriptionPaneIDs: [String] {
        guard let snapshot else { return [] }
        return Array(Set(
            snapshot.agents.map(\.paneID)
                + snapshot.ordinaryTerminalPanes.map(\.paneID)
        )).sorted()
    }

    private func applyAgentStatusEvent(_ event: HerdrEvent) -> Bool {
        guard let paneID = event.payload["data"]?["pane_id"]?.stringValue,
              let statusRaw = event.payload["data"]?["agent_status"]?.stringValue,
              let updated = snapshot?.updatingAgentStatus(
                  paneID: paneID,
                  status: AgentStatus(wire: statusRaw)
              )
        else { return false }
        if let agent = updated.agents.first(where: { $0.paneID == paneID }) { onAgents?([agent], false) }
        snapshot = updated
        statusGeneration &+= 1
        onChange?()
        return true
    }

    private static let paneTopologyEventKinds: Set<String> = [
        "pane.created",
        "pane.closed",
        "pane.moved",
        "pane.agent_detected",
    ]
}

@MainActor
@Observable
final class MobileAppModel {
    var devices: [MobileDevice] = []
    var selectedDeviceID: UUID?
    var selectedSpaceID: String?
    var selectedAgentPaneID: String?
    var showAddDevice = false
    var editingDevice: MobileDevice?
    private var agentDrafts: [AgentUnreadKey: String] = [:]
    /// Bumped by sessions to publish nested (non-Observable) state changes.
    private(set) var revision = 0

    let agentReadState: AgentReadState
    private let store: MobileDeviceStore
    private let connector: MobileTransportConnector
    private var sessions: [UUID: MobileDeviceSession] = [:]
    private var connectionTask: Task<Void, Never>?
    private var connectionTaskToken: UUID?
    private var closingTasks: [UUID: (token: UUID, task: Task<Void, Never>)] = [:]

    func agentDraft(paneID: String, deviceID: UUID) -> String {
        agentDrafts[AgentUnreadKey(deviceID: deviceID, paneID: paneID)] ?? ""
    }

    func setAgentDraft(_ text: String, paneID: String, deviceID: UUID) {
        let key = AgentUnreadKey(deviceID: deviceID, paneID: paneID)
        agentDrafts[key] = text.isEmpty ? nil : text
    }

    init(store: MobileDeviceStore? = nil, readState: AgentReadState? = nil, connector: @escaping MobileTransportConnector = { device in
        switch device.kind {
        case .ssh: return try await SSHDirectTransport.connect(device: device)
        case .tailcat: return try await TailcatMobileTransport.connect(device: device)
        }
    }) {
        agentReadState = readState ?? AgentReadState()
        self.store = store ?? MobileDeviceStore()
        self.connector = connector
        devices = self.store.load()
        selectedDeviceID = devices.first?.id
    }

    var selectedDevice: MobileDevice? {
        devices.first { $0.id == selectedDeviceID }
    }

    func session(for deviceID: UUID) -> MobileDeviceSession? {
        if let existing = sessions[deviceID] { return existing }
        guard let device = devices.first(where: { $0.id == deviceID }) else { return nil }
        let session = MobileDeviceSession(device: device, connector: connector)
        session.onChange = { [weak self] in self?.revision += 1 }
        session.onAgents = { [weak self] agents, authoritative in
            self?.agentReadState.apply(agents: agents, deviceID: deviceID, authoritative: authoritative,
                                      foreground: UIApplication.shared.applicationState == .active)
            self?.revision += 1
        }
        session.onConnectionLost = { [weak self] in
            self?.agentReadState.connectionLost(deviceID: deviceID)
        }
        sessions[deviceID] = session
        return session
    }

    var selectedSession: MobileDeviceSession? {
        guard let selectedDeviceID else { return nil }
        return session(for: selectedDeviceID)
    }

    /// Observable connection state: sessions are plain classes, so views must
    /// read this (revision-tracked) rather than session.state directly.
    var selectedConnectionState: MobileConnectionState {
        _ = revision
        return selectedSession?.state ?? .idle
    }

    func connectSelected() {
        guard let session = selectedSession else { return }
        if case .connecting = session.state { return }
        guard connectionTaskToken == nil else { return }
        let token = UUID()
        connectionTaskToken = token
        // Tailcat transports share a bridge by device ID; an obsolete close
        // must finish before the next transport can reuse that bridge.
        let precedingClose = session.device.isTailcat ? closingTasks[session.device.id]?.task : nil
        connectionTask = Task {
            await precedingClose?.value
            guard !Task.isCancelled else { return }
            await session.connect()
            if connectionTaskToken == token {
                connectionTaskToken = nil
                connectionTask = nil
            }
        }
    }

    private func cancelSelectedConnection() {
        guard let id = selectedDeviceID else { return }
        let opening = connectionTask
        connectionTask?.cancel()
        connectionTask = nil
        connectionTaskToken = nil
        let closing = selectedSession?.cancelConnection()
        let previousClose = closingTasks[id]?.task
        let token = UUID()
        let task = Task {
            await previousClose?.value
            await opening?.value
            await closing?.value
            if closingTasks[id]?.token == token { closingTasks.removeValue(forKey: id) }
        }
        closingTasks[id] = (token, task)
    }

    func selectDevice(_ id: UUID) {
        guard id != selectedDeviceID, devices.contains(where: { $0.id == id }) else { return }
        cancelSelectedConnection()
        selectedDeviceID = id
        selectedSpaceID = nil
        selectedAgentPaneID = nil
        connectSelected()
    }

    // MARK: - Device management

    func updateDevice(_ device: MobileDevice, password: String? = nil) throws {
        guard let index = devices.firstIndex(where: { $0.id == device.id }),
              devices[index].kind == device.kind else { throw MobileDeviceError.deviceNotFound }
        let validated = try device.validated()
        try savePassword(password, for: validated)
        var previousConnection = devices[index]
        previousConnection.name = validated.name
        let connectionChanged = previousConnection != validated || password?.isEmpty == false
        if connectionChanged {
            agentDrafts = agentDrafts.filter { $0.key.deviceID != device.id }
            if selectedDeviceID == device.id { cancelSelectedConnection() }
            let obsolete = sessions.removeValue(forKey: device.id)
            obsolete?.onChange = nil
            obsolete?.cancelConnection()
        } else {
            sessions[device.id]?.device = validated
        }
        devices[index] = validated
        store.save(devices)
        if connectionChanged, selectedDeviceID == device.id {
            selectedSpaceID = nil
            selectedAgentPaneID = nil
            connectSelected()
        }
        revision += 1
    }

    private func savePassword(_ password: String?, for device: MobileDevice) throws {
        guard !device.isTailcat else { return }
        if device.authMethod == .password {
            if let password, !password.isEmpty {
                try MobileSecretStore.setPassword(password, for: device.id)
            } else if MobileSecretStore.password(for: device.id)?.isEmpty != false {
                throw MobileDeviceError.missingPassword
            }
        } else {
            try MobileSecretStore.removePassword(for: device.id)
        }
    }

    func addDevice(
        name: String,
        host: String,
        port: UInt16,
        username: String,
        authMethod: MobileDevice.AuthMethod,
        password: String,
        socketPath: String? = nil,
        sshRoute: MobileDevice.SSHRoute = .direct,
        gatewayHost: String = "",
        gatewayPort: UInt16 = 8080
    ) throws {
        let device = try MobileDevice(
            name: name,
            host: host,
            port: port,
            username: username,
            authMethod: authMethod,
            socketPath: socketPath,
            sshRoute: sshRoute,
            gatewayHost: gatewayHost,
            gatewayPort: gatewayPort
        ).validated()
        try savePassword(password, for: device)
        devices.append(device)
        store.save(devices)
        selectDevice(device.id)
    }

    /// Adds a tailcat device: the token goes to the Keychain (keyed by the
    /// new device id), never into the device list. Same posture as the Mac
    /// app's `addTailcatDevice`; no host probe — tailcat has no shell.
    func addTailcatDevice(name: String, token: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = MobileDevice(
            kind: .tailcat,
            name: trimmedName.isEmpty ? AppLocalization.string("Tailcat device") : trimmedName
        )
        do {
            try TailcatCredentialStore.setToken(token, for: device.id)
        } catch {
            return
        }
        devices.append(device)
        store.save(devices)
        selectDevice(device.id)
    }

    /// The line to enroll on a Mac: `echo '<line>' >> ~/.ssh/authorized_keys`.
    var deviceKeyAuthorizedLine: String {
        DeviceKey.authorizedKeysLine(DeviceKey.ensure())
    }

    /// This install's tailcat client public key ("nodekey:…") for a host's
    /// allow.list. Loaded lazily by the tailcat UI so SSH-only installs never
    /// create a client key.
    private(set) var tailcatClientPublicKey: String?
    /// Why the client key could not be read or replaced; shown in its place.
    private(set) var tailcatClientKeyError: String?

    func loadTailcatClientPublicKey() {
        guard tailcatClientPublicKey == nil else { return }
        do {
            tailcatClientPublicKey = try TailcatClientKeyStore.publicKey()
            tailcatClientKeyError = nil
        } catch {
            tailcatClientKeyError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Replaces the shared client key, then restarts every tailcat bridge so
    /// it picks up the new identity: `ensureUp` hands back a live bridge
    /// as-is, so each one must be torn down before the reconnect.
    func regenerateTailcatClientKey() {
        do {
            tailcatClientPublicKey = try TailcatClientKeyStore.regenerate()
            tailcatClientKeyError = nil
        } catch {
            tailcatClientKeyError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return
        }
        let tailcatIDs = devices.filter(\.isTailcat).map(\.id)
        let dropped = tailcatIDs.compactMap { sessions.removeValue(forKey: $0) }
        let reconnectSelected = selectedDevice?.isTailcat == true
        Task {
            // Sequential on purpose: sessions close, then bridges go down,
            // and only then does the selected device reconnect.
            for session in dropped {
                await session.disconnect()
            }
            for id in tailcatIDs {
                await TailcatBridgeManager.shared.tearDown(deviceID: id)
            }
            if reconnectSelected {
                connectSelected()
            }
        }
    }

    func removeDevice(_ device: MobileDevice) throws {
        guard let saved = devices.first(where: { $0.id == device.id }) else {
            throw MobileDeviceError.deviceNotFound
        }
        try MobileSecretStore.removePassword(for: device.id)
        if selectedDeviceID == device.id { cancelSelectedConnection() }
        if let session = sessions.removeValue(forKey: device.id) {
            session.onChange = nil
            session.cancelConnection()
        }
        if saved.isTailcat {
            TailcatCredentialStore.removeToken(for: device.id)
            Task { await TailcatBridgeManager.shared.tearDown(deviceID: device.id) }
        }
        agentReadState.removeDevice(device.id)
        devices.removeAll { $0.id == device.id }
        agentDrafts = agentDrafts.filter { $0.key.deviceID != device.id }
        if !saved.isTailcat, !devices.contains(where: {
            !$0.isTailcat && $0.host == saved.host && $0.port == saved.port
        }) {
            KnownHostsStore.unpin(host: saved.host, port: saved.port)
        }
        store.save(devices)
        if selectedDeviceID == device.id {
            selectedDeviceID = devices.first?.id
            selectedSpaceID = nil
            selectedAgentPaneID = nil
            connectSelected()
        }
    }

    func isUnread(_ agent: AgentInfo) -> Bool {
        _ = revision
        guard let selectedDeviceID else { return false }
        return agentReadState.unread.contains(AgentUnreadKey(deviceID: selectedDeviceID, paneID: agent.paneID))
    }

    func attention(for spaceID: String) -> SpaceAttention {
        _ = revision
        return SpaceAttention.rollup((selectedSession?.snapshot?.agents ?? [])
            .filter { $0.workspaceID == spaceID }
            .map { (status: $0.status, unreadDone: isUnread($0)) })
    }

    func terminalReadStateChanged() { revision += 1 }

    // MARK: - Derived lists (mirror the Mac sidebar)

    var spaces: [WorkspaceInfo] {
        _ = revision
        return selectedSession?.snapshot?.workspaces ?? []
    }

    /// Agents in the selected space (nil = all), waiting-on-you first —
    /// the same Blocked > Done > Working > Idle order as the Mac app and Heeler.
    var agents: [AgentInfo] {
        _ = revision
        guard let snapshot = selectedSession?.snapshot else { return [] }
        var list = snapshot.agents
        if let selectedSpaceID {
            list = list.filter { $0.workspaceID == selectedSpaceID }
        }
        return list.sorted {
            if $0.status.sortBucket != $1.status.sortBucket {
                return $0.status.sortBucket < $1.status.sortBucket
            }
            return $0.paneID < $1.paneID
        }
    }

    func tabLabel(for agent: AgentInfo) -> String? {
        _ = revision
        return selectedSession?.snapshot?.tabs?
            .first { $0.tabID == agent.tabID }?.customLabel
    }

    func spaceName(for workspaceID: String) -> String {
        _ = revision
        return selectedSession?.snapshot?.workspaces
            .first { $0.workspaceID == workspaceID }?.label ?? workspaceID
    }

    var selectedAgent: AgentInfo? {
        _ = revision
        return selectedSession?.snapshot?.agents.first { $0.paneID == selectedAgentPaneID }
    }

    /// Bare herdr terminal panes in the selected space (nil = all).
    var terminalPanes: [PaneInfo] {
        _ = revision
        guard let snapshot = selectedSession?.snapshot else { return [] }
        var panes = snapshot.ordinaryTerminalPanes
        if let selectedSpaceID {
            panes = panes.filter { $0.workspaceID == selectedSpaceID }
        }
        return panes.sorted { $0.paneID < $1.paneID }
    }

    var selectedTerminalPane: PaneInfo? {
        _ = revision
        return terminalPanes.first { $0.paneID == selectedAgentPaneID }
    }

    func terminalLabel(for pane: PaneInfo) -> String {
        _ = revision
        if let tabID = pane.tabID,
           let label = selectedSession?.snapshot?.tabs?
               .first(where: { $0.tabID == tabID })?.customLabel {
            return label
        }
        if let title = pane.terminalTitle, !title.isEmpty { return title }
        return AppLocalization.string("Terminal")
    }
}
