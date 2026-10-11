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

struct MobileWorkspaceTab: Identifiable {
    let id: String
    let label: String
}

struct MobilePaneChoice: Identifiable {
    let id: String
    let title: String
    let agent: AgentInfo?
}

enum MobilePaneMode: String { case chat, terminal }

struct MobilePromptTarget: Hashable {
    let deviceID: UUID
    let presentationID: UUID
    let connectionID: UUID
    let spaceID: String
    let tabID: String
    let paneID: String
}

struct MobilePaneContext: Hashable {
    let deviceID: UUID
    let presentationID: UUID
    let spaceID: String
    let tabID: String
    let paneID: String
    init(_ target: MobilePromptTarget) {
        deviceID = target.deviceID; presentationID = target.presentationID
        spaceID = target.spaceID; tabID = target.tabID; paneID = target.paneID
    }
}

enum MobilePromptResult: Equatable { case acknowledged, failed, targetChanged, unavailable, busy }

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
    private var snapshotEpoch: UInt64 = 0
    private let connector: MobileTransportConnector
    private var connectToken: UUID?
    private var validationToken: UUID?
    private var validationTask: Task<Void, Never>?
    private var validationDeadlineTask: Task<Void, Never>?
    private(set) var isValidating = false

    var actionsReady: Bool {
        if case .connected = state { return !isValidating }
        return false
    }

    /// A foreground return validates the held control channel before input or
    /// read acknowledgement resumes. A healthy SSH/PTY is never reopened.
    func resume(timeout: Duration = .seconds(3)) {
        guard case .connected = state, transport != nil else {
            Task { await connect() }
            return
        }
        guard !isValidating else { return }
        isValidating = true
        invalidateSnapshotRefresh()
        let token = UUID()
        validationToken = token
        onChange?()
        validationTask = Task { [weak self] in
            guard let self else { return }
            let succeeded = await self.refresh()
            guard self.validationToken == token, !Task.isCancelled else { return }
            self.finishValidation(token: token, succeeded: succeeded)
        }
        validationDeadlineTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self, !Task.isCancelled, self.validationToken == token else { return }
            self.finishValidation(token: token, succeeded: false)
        }
    }

    private func finishValidation(token: UUID, succeeded: Bool) {
        guard validationToken == token else { return }
        validationToken = nil
        validationDeadlineTask?.cancel()
        validationTask?.cancel()
        validationDeadlineTask = nil
        validationTask = nil
        isValidating = false
        if succeeded, case .connected = state { onChange?(); return }
        state = .failed(AppLocalization.string("Connection lost"))
        onChange?()
        Task { await connect() }
    }

    func prepareForResume() {
        if validationToken == nil { isValidating = false }
    }

    func suspendPresentation() {
        // Keep transport and renderer; make pending presentation proofs invalid.
        isValidating = true
        validationToken = nil
        validationTask?.cancel()
        validationDeadlineTask?.cancel()
        invalidateSnapshotRefresh()
        onChange?()
    }

    private func invalidateSnapshotRefresh() {
        snapshotEpoch &+= 1
        snapshotRefreshTask?.cancel()
        snapshotRefreshTask = nil
        snapshotRefreshToken = nil
        refreshRequested = false
    }

    var onChange: (() -> Void)?
    var onAgents: (([AgentInfo], Bool) -> Void)?
    var onConnectionLost: (() -> Void)?
    private(set) var connectionID = UUID()
    /// Stable across reconnects, replaced with the session on configuration edits.
    let presentationID = UUID()

    init(device: MobileDevice, connector: @escaping MobileTransportConnector) {
        self.device = device
        self.connector = connector
    }

    func connect() async {
        guard !Task.isCancelled else { return }
        if case .connected = state { resume(); return }
        guard case .connecting = state else {
            let token = UUID()
            connectToken = token
            connectionID = UUID()
            onConnectionLost?()
            state = .connecting
            let oldTransport = self.transport
            // Retain the old renderer's transport identity while restoring.
            // It is input-disabled and cannot acknowledge cached content.
            eventTask?.cancel()
            invalidateSnapshotRefresh()
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
                isValidating = true
                state = .connected(version: pong.version)
                let refreshed = await refresh()
                guard connectToken == token, !Task.isCancelled else { return }
                guard refreshed else { throw HerdrError.connectionFailed("snapshot unavailable") }
                isValidating = false
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
        validationToken = nil
        validationTask?.cancel()
        validationDeadlineTask?.cancel()
        isValidating = false
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
        let connection = connectionID
        let epoch = snapshotEpoch
        struct Envelope: Codable { let snapshot: SessionSnapshot }
        do {
            let fetched = try await transport.request(
                method: "session.snapshot", as: Envelope.self
            ).snapshot
            guard !Task.isCancelled, self.transport === transport, self.connectionID == connection, self.snapshotEpoch == epoch else {
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
    var selectedTabID: String?
    private struct SpaceKey: Hashable { let deviceID: UUID; let spaceID: String }
    private struct TabKey: Hashable { let deviceID: UUID; let spaceID: String; let tabID: String }
    private var rememberedSpaces: [UUID: String] = [:]
    private var rememberedTabs: [SpaceKey: String] = [:]
    private var rememberedPanes: [TabKey: String] = [:]
    private var completionStatuses: [AgentUnreadKey: AgentStatus] = [:]
    private var completionRevisions: [AgentUnreadKey: UInt64] = [:]
    private var knownPaneTitles: [AgentUnreadKey: String] = [:]
    var showAddDevice = false
    var editingDevice: MobileDevice?
    private var agentDrafts: [AgentUnreadKey: String] = [:]
    private var paneModes: [MobilePromptTarget: MobilePaneMode] = [:]
    private var submitting: Set<MobilePromptTarget> = []
    @ObservationIgnored private var chatDrafts: [MobilePaneContext: MobileChatDraft] = [:]

    func chatDraft(for target: MobilePromptTarget) -> MobileChatDraft {
        let key = MobilePaneContext(target)
        if let draft = chatDrafts[key] { return draft }
        let draft = MobileChatDraft()
        chatDrafts[key] = draft
        return draft
    }

    func invalidateChat(for deviceID: UUID) {
        for (key, draft) in chatDrafts where key.deviceID == deviceID { draft.invalidate() }
        chatDrafts = chatDrafts.filter { $0.key.deviceID != deviceID }
        paneModes = paneModes.filter { $0.key.deviceID != deviceID }
        completionStatuses = completionStatuses.filter { $0.key.deviceID != deviceID }
        completionRevisions = completionRevisions.filter { $0.key.deviceID != deviceID }
    }

    var currentPromptTarget: MobilePromptTarget? {
        guard let deviceID = selectedDeviceID, let session = selectedSession,
              let spaceID = selectedSpaceID, let tabID = selectedTabID,
              let paneID = selectedAgentPaneID, !selectedTargetUnavailable else { return nil }
        return MobilePromptTarget(deviceID: deviceID, presentationID: session.presentationID,
            connectionID: session.connectionID, spaceID: spaceID, tabID: tabID, paneID: paneID)
    }

    var paneMode: MobilePaneMode {
        guard let target = currentPromptTarget else { return .terminal }
        // Reconnects preserve presentation identity and the user's mode.
        return paneModes.first { $0.key.deviceID == target.deviceID && $0.key.presentationID == target.presentationID &&
            $0.key.spaceID == target.spaceID && $0.key.tabID == target.tabID && $0.key.paneID == target.paneID }?.value
            ?? (selectedAgent == nil ? .terminal : .chat)
    }

    func selectMode(_ mode: MobilePaneMode) {
        guard let target = currentPromptTarget, mode == .terminal || selectedAgent != nil else { return }
        paneModes = paneModes.filter { !($0.key.deviceID == target.deviceID && $0.key.paneID == target.paneID) }
        paneModes[target] = mode
    }

    func isSubmitting(_ target: MobilePromptTarget) -> Bool { submitting.contains(target) }

    /// A single acknowledged SSH submission. An uncertain request is never replayed.
    func submitPrompt(target: MobilePromptTarget, attachmentPaths: [String] = []) async -> MobilePromptResult {
        guard currentPromptTarget == target, selectedAgent != nil, selectedTransportReady,
              let session = selectedSession, let transport = session.transport else { return .unavailable }
        guard !submitting.contains(target) else { return .busy }
        let original = agentDraft(paneID: target.paneID, deviceID: target.deviceID)
        let text = ([original.trimmingCharacters(in: .whitespacesAndNewlines)] + attachmentPaths.map { "@" + $0 })
            .filter { !$0.isEmpty }.joined(separator: "\n")
        guard !text.isEmpty else { return .unavailable }
        submitting.insert(target)
        defer { submitting.remove(target) }
        do {
            _ = try await transport.request(method: "agent.prompt", params: .object([
                "target": .string(target.paneID), "text": .string(text)
            ]))
        } catch { return .failed }
        guard currentPromptTarget == target, session.transport === transport else { return .targetChanged }
        if agentDraft(paneID: target.paneID, deviceID: target.deviceID) == original {
            setAgentDraft("", paneID: target.paneID, deviceID: target.deviceID)
        }
        return .acknowledged
    }
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

    private func observeChatCompletions(agents: [AgentInfo], deviceID: UUID, authoritative: Bool) {
        for agent in agents {
            let key = AgentUnreadKey(deviceID: deviceID, paneID: agent.paneID)
            if let previous = completionStatuses[key], previous != .done, agent.status == .done {
                completionRevisions[key, default: 0] &+= 1
            }
            completionStatuses[key] = agent.status
        }
        if authoritative {
            let live = Set(agents.map(\.paneID))
            completionStatuses = completionStatuses.filter { $0.key.deviceID != deviceID || live.contains($0.key.paneID) }
            completionRevisions = completionRevisions.filter { $0.key.deviceID != deviceID || live.contains($0.key.paneID) }
        }
    }

    func chatCompletionRevision(for target: MobilePromptTarget) -> UInt64 {
        _ = revision
        return completionRevisions[AgentUnreadKey(deviceID: target.deviceID, paneID: target.paneID)] ?? 0
    }

    var selectedDevice: MobileDevice? {
        devices.first { $0.id == selectedDeviceID }
    }

    func session(for deviceID: UUID) -> MobileDeviceSession? {
        if let existing = sessions[deviceID] { return existing }
        guard let device = devices.first(where: { $0.id == deviceID }) else { return nil }
        let session = MobileDeviceSession(device: device, connector: connector)
        session.onChange = { [weak self] in
            guard let self else { return }
            self.revision += 1
            if self.selectedDeviceID == deviceID { self.reconcileNavigation() }
        }
        session.onAgents = { [weak self, weak session] agents, authoritative in
            self?.observeChatCompletions(agents: agents, deviceID: deviceID, authoritative: authoritative)
            self?.agentReadState.apply(agents: agents, deviceID: deviceID, authoritative: authoritative,
                                      foreground: UIApplication.shared.applicationState == .active && session?.actionsReady == true)
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

    func resumeSelected(validationTimeout: Duration = .seconds(3)) {
        guard let session = selectedSession, connectionTaskToken == nil else { return }
        if case .connected = session.state {
            // suspendPresentation has gated proof/input but did not start validation.
            session.prepareForResume()
            session.resume(timeout: validationTimeout)
        } else { connectSelected() }
    }

    func suspendSelected() { selectedSession?.suspendPresentation() }

    var selectedTransportReady: Bool {
        _ = revision
        return selectedSession?.actionsReady == true
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
        selectedTabID = nil
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
        previousConnection.chatConfiguration = validated.chatConfiguration
        let chatChanged = devices[index].chatConfiguration != validated.chatConfiguration
        if chatChanged { invalidateChat(for: device.id) }
        let connectionChanged = previousConnection != validated || password?.isEmpty == false
        if connectionChanged {
            agentReadState.removeDevice(device.id)
            clearNavigationHistory(for: device.id)
            agentDrafts = agentDrafts.filter { $0.key.deviceID != device.id }
            invalidateChat(for: device.id)
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
            selectedTabID = nil
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
        clearNavigationHistory(for: device.id)
        devices.removeAll { $0.id == device.id }
        agentDrafts = agentDrafts.filter { $0.key.deviceID != device.id }
        invalidateChat(for: device.id)
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
            selectedTabID = nil
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

    var selectedSpace: WorkspaceInfo? { spaces.first { $0.workspaceID == selectedSpaceID } }

    /// Server tab order is independent of Agent status sorting.
    var workspaceTabs: [MobileWorkspaceTab] {
        _ = revision
        guard let spaceID = selectedSpaceID, let snapshot = selectedSession?.snapshot else { return [] }
        if let tabs = snapshot.tabs {
            return tabs.enumerated().filter { $0.element.workspaceID == spaceID }
                .sorted {
                    let a = $0.element.number ?? Int.max, b = $1.element.number ?? Int.max
                    return a == b ? $0.offset < $1.offset : a < b
                }
                .map { MobileWorkspaceTab(id: $0.element.tabID, label: $0.element.label) }
        }
        // Older servers may omit tabs. Preserve actual pane tab IDs and titles.
        var result: [MobileWorkspaceTab] = []
        for agent in snapshot.agents where agent.workspaceID == spaceID {
            if !result.contains(where: { $0.id == agent.tabID }) {
                result.append(MobileWorkspaceTab(id: agent.tabID, label: agent.title))
            }
        }
        for pane in snapshot.ordinaryTerminalPanes where pane.workspaceID == spaceID {
            if let id = pane.tabID, !result.contains(where: { $0.id == id }) {
                result.append(MobileWorkspaceTab(id: id, label: terminalLabel(for: pane)))
            }
        }
        return result
    }

    func paneChoices(in tabID: String) -> [MobilePaneChoice] {
        _ = revision
        guard let spaceID = selectedSpaceID, let snapshot = selectedSession?.snapshot else { return [] }
        let agents = snapshot.agents.filter { $0.workspaceID == spaceID && $0.tabID == tabID }
        let shells = snapshot.ordinaryTerminalPanes.filter { $0.workspaceID == spaceID && $0.tabID == tabID }
        let choices = agents.map { MobilePaneChoice(id: $0.paneID, title: $0.title, agent: $0) }
            + shells.map { MobilePaneChoice(id: $0.paneID, title: $0.terminalTitle ?? terminalLabel(for: $0), agent: nil) }
        // Snapshot panes provide actual split order when available.
        let order = (snapshot.panes ?? []).map(\.paneID)
        return choices.sorted { (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max) }
    }

    func tabAttention(for tabID: String) -> SpaceAttention {
        SpaceAttention.rollup(paneChoices(in: tabID).compactMap(\.agent)
            .map { (status: $0.status, unreadDone: isUnread($0)) })
    }

    var selectedPaneTitle: String? {
        _ = revision
        guard let deviceID = selectedDeviceID, let paneID = selectedAgentPaneID else { return nil }
        return knownPaneTitles[AgentUnreadKey(deviceID: deviceID, paneID: paneID)]
    }

    var hasCurrentSnapshot: Bool {
        _ = revision
        return selectedSession?.snapshot != nil
    }

    /// Only an authoritative current snapshot can declare a chosen target gone.
    var selectedTargetUnavailable: Bool {
        guard hasCurrentSnapshot, case .connected = selectedConnectionState else { return false }
        if let spaceID = selectedSpaceID, !spaces.contains(where: { $0.workspaceID == spaceID }) { return true }
        if let tabID = selectedTabID {
            if !workspaceTabs.contains(where: { $0.id == tabID }) { return true }
            if let paneID = selectedAgentPaneID, !paneChoices(in: tabID).contains(where: { $0.id == paneID }) { return true }
        }
        return false
    }

    func selectSpace(_ id: String) {
        guard spaces.contains(where: { $0.workspaceID == id }), let deviceID = selectedDeviceID else { return }
        selectedSpaceID = id
        rememberedSpaces[deviceID] = id
        selectedTabID = nil
        selectedAgentPaneID = nil
        reconcileNavigation()
    }

    func selectTab(_ id: String) {
        guard workspaceTabs.contains(where: { $0.id == id }),
              let deviceID = selectedDeviceID, let spaceID = selectedSpaceID else { return }
        selectedTabID = id
        rememberedTabs[SpaceKey(deviceID: deviceID, spaceID: spaceID)] = id
        selectedAgentPaneID = nil
        reconcileNavigation()
    }

    func selectPane(_ id: String) {
        guard let tabID = selectedTabID, paneChoices(in: tabID).contains(where: { $0.id == id }),
              let deviceID = selectedDeviceID, let spaceID = selectedSpaceID else { return }
        selectedAgentPaneID = id
        rememberedPanes[TabKey(deviceID: deviceID, spaceID: spaceID, tabID: tabID)] = id
        rememberPaneTitle()
    }

    private func rememberPaneTitle() {
        guard let deviceID = selectedDeviceID, let tabID = selectedTabID,
              let choice = paneChoices(in: tabID).first(where: { $0.id == selectedAgentPaneID }) else { return }
        knownPaneTitles[AgentUnreadKey(deviceID: deviceID, paneID: choice.id)] = choice.title
    }

    private func clearNavigationHistory(for deviceID: UUID) {
        rememberedSpaces.removeValue(forKey: deviceID)
        rememberedTabs = rememberedTabs.filter { $0.key.deviceID != deviceID }
        rememberedPanes = rememberedPanes.filter { $0.key.deviceID != deviceID }
        knownPaneTitles = knownPaneTitles.filter { $0.key.deviceID != deviceID }
    }

    private func reconcileNavigation() {
        guard case .connected = selectedConnectionState, let deviceID = selectedDeviceID,
              let snapshot = selectedSession?.snapshot else { return }
        // A deletion must not silently attach the phone to a different target.
        // An explicit Space/Tab/pane choice clears or replaces these identities.
        if let spaceID = selectedSpaceID, !snapshot.workspaces.contains(where: { $0.workspaceID == spaceID }) { return }
        if !snapshot.workspaces.contains(where: { $0.workspaceID == selectedSpaceID }) {
            selectedSpaceID = snapshot.workspaces.first { $0.workspaceID == rememberedSpaces[deviceID] }?.workspaceID
                ?? snapshot.workspaces.first { $0.workspaceID == snapshot.focusedWorkspaceID }?.workspaceID
                ?? snapshot.workspaces.first(where: { $0.focused == true })?.workspaceID
                ?? snapshot.workspaces.first?.workspaceID
            selectedTabID = nil
            selectedAgentPaneID = nil
        }
        guard let spaceID = selectedSpaceID else { return }
        let spaceKey = SpaceKey(deviceID: deviceID, spaceID: spaceID)
        rememberedSpaces[deviceID] = spaceID
        if let tabID = selectedTabID, !workspaceTabs.contains(where: { $0.id == tabID }) { return }
        if !workspaceTabs.contains(where: { $0.id == selectedTabID }) {
            selectedTabID = workspaceTabs.first { $0.id == rememberedTabs[spaceKey] }?.id
                ?? workspaceTabs.first { $0.id == selectedSpace?.activeTabID }?.id
                ?? snapshot.tabs?.first { $0.workspaceID == spaceID && $0.focused == true }?.tabID
                ?? workspaceTabs.first?.id
            selectedAgentPaneID = nil
        }
        guard let tabID = selectedTabID else { return }
        rememberedTabs[spaceKey] = tabID
        let tabKey = TabKey(deviceID: deviceID, spaceID: spaceID, tabID: tabID)
        let choices = paneChoices(in: tabID)
        if let paneID = selectedAgentPaneID, !choices.contains(where: { $0.id == paneID }) { return }
        if !choices.contains(where: { $0.id == selectedAgentPaneID }) {
            selectedAgentPaneID = choices.first { $0.id == rememberedPanes[tabKey] }?.id
                ?? choices.first { $0.id == snapshot.focusedPaneID }?.id
                ?? choices.first { $0.agent?.focused == true }?.id
                ?? choices.first?.id
        }
        if let paneID = selectedAgentPaneID { rememberedPanes[tabKey] = paneID }
        rememberPaneTitle()
    }

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
        return agents.first { $0.paneID == selectedAgentPaneID && $0.tabID == selectedTabID }
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
        return terminalPanes.first { $0.paneID == selectedAgentPaneID && $0.tabID == selectedTabID }
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
