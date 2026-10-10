import HerdrKit
import SwiftUI

/// iPhone: a navigation stack (lists → terminal). iPad: a split view whose
/// sidebar mirrors the Mac app — Spaces, Agents, and a device switcher footer.
struct MobileRootView: View {
    @Bindable var model: MobileAppModel
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            SidebarListView(model: model)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
        } detail: {
            if let device = model.selectedDevice, device.isTailcat,
               model.selectedAgentPaneID != nil {
                // tailcat carries herdr's control plane only — no shell, no
                // PTY channel — so there is no terminal byte stream to attach
                // to on iOS. Prompting stays available from the agent's row.
                ContentUnavailableView(
                    AppLocalization.string("No Terminal over Tailcat"),
                    systemImage: "terminal",
                    description: Text(AppLocalization.string("This device's tunnel reaches herdr's control plane only. Use an SSH device to attach to a live terminal."))
                )
            } else if let agent = model.selectedAgent,
               let transport = model.selectedSession?.transport {
                MobileTerminalScreen(
                    transport: transport,
                    target: .agent(paneID: agent.paneID),
                    paneID: agent.paneID,
                    title: agent.title(tabLabel: model.tabLabel(for: agent)),
                    readState: model.agentReadState,
                    unreadKey: model.selectedDeviceID.map { AgentUnreadKey(deviceID: $0, paneID: agent.paneID) },
                    onReadStateChanged: { model.terminalReadStateChanged() }
                )
                .id("\(model.selectedDeviceID?.uuidString ?? "")-\(agent.paneID)-\(model.selectedSession?.connectionID.uuidString ?? "")")
            } else if let pane = model.selectedTerminalPane,
                      let terminalID = pane.terminalID,
                      let transport = model.selectedSession?.transport {
                MobileTerminalScreen(
                    transport: transport,
                    target: .terminal(terminalID: terminalID),
                    paneID: pane.paneID,
                    title: model.terminalLabel(for: pane)
                )
                .id("\(model.selectedDeviceID?.uuidString ?? "")-\(pane.paneID)-\(model.selectedSession?.connectionID.uuidString ?? "")")
            } else {
                ContentUnavailableView(
                    AppLocalization.string("No Agent Selected"),
                    systemImage: "terminal",
                    description: Text(AppLocalization.string("Pick an agent to attach to its terminal."))
                )
            }
        }
        .sheet(isPresented: $model.showAddDevice) {
            DeviceEditorSheet(model: model)
        }
        .sheet(isPresented: $showSettings) {
            MobileSettingsView()
        }
        .sheet(item: $model.editingDevice) { device in
            DeviceEditorSheet(model: model, device: device)
        }
        .task {
            if model.selectedDeviceID != nil { model.connectSelected() }
        }
    }
}

private struct SidebarListView: View {
    @Bindable var model: MobileAppModel

    var body: some View {
        List(selection: $model.selectedAgentPaneID) {
            if model.devices.isEmpty {
                ContentUnavailableView {
                    Label(AppLocalization.string("No Devices"), systemImage: "desktopcomputer")
                } description: {
                    Text(AppLocalization.string("Add a development machine running herdr to get started."))
                } actions: {
                    Button(AppLocalization.string("Add Device")) { model.showAddDevice = true }
                        .buttonStyle(.borderedProminent)
                }
                .listRowSeparator(.hidden)
            } else {
                connectionSection
                spacesSection
                agentsSection
                terminalsSection
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("herdrm")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                DeviceSwitcherMenu(model: model)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.showAddDevice = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable {
            await model.selectedSession?.refresh()
        }
    }

    @ViewBuilder
    private var connectionSection: some View {
        if model.selectedSession != nil {
            switch model.selectedConnectionState {
            case .idle, .connecting:
                HStack(spacing: 8) {
                    ProgressView()
                    Text(AppLocalization.string("Connecting…"))
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
            case .failed(let reason):
                VStack(alignment: .leading, spacing: 8) {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(AppLocalization.string("Reconnect")) { model.connectSelected() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .listRowSeparator(.hidden)
            case .connected:
                EmptyView()
            }
        }
    }

    private var spacesSection: some View {
        Section(AppLocalization.string("Spaces")) {
            Button {
                model.selectedSpaceID = nil
            } label: {
                SpaceRow(
                    label: AppLocalization.string("All Spaces"),
                    systemImage: "square.grid.2x2",
                    count: model.spaces.count,
                    selected: model.selectedSpaceID == nil
                )
            }
            .buttonStyle(.plain)
            ForEach(model.spaces) { space in
                Button {
                    model.selectedSpaceID = space.workspaceID
                } label: {
                    SpaceRow(
                        label: space.label,
                        systemImage: "folder",
                        count: nil,
                        selected: model.selectedSpaceID == space.workspaceID
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var terminalsSection: some View {
        if !model.terminalPanes.isEmpty {
            Section(AppLocalization.string("Terminals")) {
                ForEach(model.terminalPanes) { pane in
                    NavigationLink(value: pane.paneID) {
                        HStack(spacing: 10) {
                            Image(systemName: "terminal")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.terminalLabel(for: pane))
                                    .lineLimit(1)
                                Text(model.spaceName(for: pane.workspaceID))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    private var agentsSection: some View {
        Section(AppLocalization.string("Agents")) {
            if model.agents.isEmpty {
                Text(AppLocalization.string("No agents"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            ForEach(model.agents) { agent in
                NavigationLink(value: agent.paneID) {
                    AgentRow(
                        agent: agent,
                        title: agent.title(tabLabel: model.tabLabel(for: agent)),
                        spaceName: model.spaceName(for: agent.workspaceID),
                        unread: model.isUnread(agent)
                    )
                }
            }
        }
    }
}

private struct SpaceRow: View {
    let label: String
    let systemImage: String
    let count: Int?
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            Text(label)
                .fontWeight(selected ? .semibold : .regular)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct AgentRow: View {
    let agent: AgentInfo
    let title: String
    let spaceName: String
    var unread = false

    var body: some View {
        HStack(spacing: 10) {
            if unread && agent.status == .done {
                Circle().fill(.blue).frame(width: 8, height: 8).frame(width: 20)
                    .accessibilityLabel(AppLocalization.string("Completed, unread"))
            } else {
                StatusGlyph(status: agent.status)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(agent.agent)
                    Text("·")
                    Text(spaceName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            if agent.status == .blocked {
                Text(AppLocalization.string("needs input"))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// The Mac app's status marks, phone-sized: spinner while working, exclamation
/// when the agent waits on you, check when done, dot when idle.
private struct StatusGlyph: View {
    let status: AgentStatus

    var body: some View {
        switch status {
        case .working:
            ProgressView().controlSize(.small)
        case .blocked:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .idle, .unknown:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }
}

/// Top-left device switcher: a compact chip naming the current device, with
/// the device list, add, and remove actions in its menu.
private struct DeviceSwitcherMenu: View {
    @Bindable var model: MobileAppModel
    @State private var confirmRemove = false
    @State private var removalError: String?

    var body: some View {
        if let device = model.selectedDevice {
            Menu {
                ForEach(model.devices) { candidate in
                    Button {
                        model.selectDevice(candidate.id)
                    } label: {
                        if candidate.id == model.selectedDeviceID {
                            Label(candidate.name, systemImage: "checkmark")
                        } else {
                            Text(candidate.name)
                        }
                    }
                }
                Divider()
                Button(AppLocalization.string("Add Device…")) { model.showAddDevice = true }
                if let selected = model.selectedDevice {
                    Button(AppLocalization.string("Edit Device…")) { model.editingDevice = selected }
                    Button(AppLocalization.string("Remove \(selected.name)"), role: .destructive) {
                        confirmRemove = true
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    ConnectionDot(state: model.selectedConnectionState)
                    Text(device.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .confirmationDialog(AppLocalization.string("Remove this device?"), isPresented: $confirmRemove, titleVisibility: .visible) {
                Button(AppLocalization.string("Remove Device"), role: .destructive) {
                    do { try model.removeDevice(device) }
                    catch { removalError = error.localizedDescription }
                }
            } message: {
                Text(AppLocalization.string("This removes its local configuration and credentials. The phone's shared SSH key is kept. To revoke remote access, remove this phone's public key from the server's authorized_keys separately."))
            }
            .alert(AppLocalization.string("Could Not Remove Device"), isPresented: Binding(
                get: { removalError != nil }, set: { if !$0 { removalError = nil } }
            )) {
                Button(AppLocalization.string("OK"), role: .cancel) { removalError = nil }
            } message: { Text(removalError ?? "") }
        }
    }
}

private struct ConnectionDot: View {
    let state: MobileConnectionState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch state {
        case .connected: return .green
        case .connecting: return .yellow
        case .failed: return .red
        case .idle: return .gray
        }
    }
}

struct DeviceEditorSheet: View {
    @Bindable var model: MobileAppModel
    let device: MobileDevice?
    @Environment(\.dismiss) private var dismiss
    @State private var kind: MobileDevice.Kind = .ssh
    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authMethod: MobileDevice.AuthMethod = .deviceKey
    @State private var password = ""
    @State private var socketPath = ""
    @State private var saveError: String?
    @State private var tailcatToken = ""
    @State private var copiedKey = false
    @State private var copiedClientKey = false
    @State private var confirmRegenerateClientKey = false

    init(model: MobileAppModel, device: MobileDevice? = nil) {
        self.model = model
        self.device = device
        _kind = State(initialValue: device?.kind ?? .ssh)
        _name = State(initialValue: device?.name ?? "")
        _host = State(initialValue: device?.host ?? "")
        _port = State(initialValue: String(device?.port ?? 22))
        _username = State(initialValue: device?.username ?? "")
        _authMethod = State(initialValue: device?.authMethod ?? .deviceKey)
        _socketPath = State(initialValue: device?.socketPath ?? "")
    }

    private var validationError: String? {
        guard kind == .ssh else { return nil }
        do {
            let parsed = try parsedSSHPort()
            _ = try MobileDevice(name: name, host: host, port: parsed, username: username).validated()
            if authMethod == .password, password.isEmpty, device?.authMethod != .password {
                return MobileDeviceError.missingPassword.localizedDescription
            }
            return nil
        } catch { return error.localizedDescription }
    }

    private func parsedSSHPort() throws -> UInt16 {
        guard let parsed = UInt16(port.trimmingCharacters(in: .whitespacesAndNewlines)), parsed > 0 else {
            throw MobileDeviceError.invalidPort
        }
        return parsed
    }

    private var canAdd: Bool {
        switch kind {
        case .ssh:
            return validationError == nil
        case .tailcat:
            return device != nil || !tailcatToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(AppLocalization.string("Connection"), selection: $kind) {
                        Text(AppLocalization.string("SSH")).tag(MobileDevice.Kind.ssh)
                        Text(AppLocalization.string("Tailcat")).tag(MobileDevice.Kind.tailcat)
                    }
                    .disabled(device != nil)
                }

                Section(AppLocalization.string("Device")) {
                    TextField(AppLocalization.string("Name (optional)"), text: $name)
                    if kind == .ssh {
                        TextField(AppLocalization.string("Host or IP"), text: $host)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField(AppLocalization.string("Port"), text: $port)
                            .keyboardType(.numberPad)
                    }
                }

                if kind == .tailcat, device == nil {
                    Section {
                        SecureField(AppLocalization.string("Token"), text: $tailcatToken)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text(AppLocalization.string("Tailcat Token"))
                    } footer: {
                        Text(AppLocalization.string("From the host: herdr plugin action invoke herdr.tailcat.token — the token is stored in this device's Keychain, and the tunnel needs no SSH."))
                    }
                    tailcatClientKeySection
                } else if kind == .ssh {
                    sshSections
                }
                if let validationError {
                    Section { Text(validationError).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(device == nil ? AppLocalization.string("Add Device") : AppLocalization.string("Edit Device"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(device == nil ? AppLocalization.string("Add") : AppLocalization.string("Save")) {
                        do {
                            if var edited = device {
                                edited.name = name
                                if kind == .ssh {
                                    edited.host = host
                                    edited.port = try parsedSSHPort()
                                    edited.username = username
                                    edited.authMethod = authMethod
                                    edited.socketPath = socketPath
                                }
                                try model.updateDevice(edited, password: password.isEmpty ? nil : password)
                            } else if kind == .ssh {
                                try model.addDevice(
                                    name: name,
                                    host: host,
                                    port: try parsedSSHPort(),
                                    username: username,
                                    authMethod: authMethod,
                                    password: password,
                                    socketPath: socketPath
                                )
                            } else {
                                model.addTailcatDevice(name: name, token: tailcatToken)
                            }
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                    .disabled(!canAdd)
                }
            }
            .alert(AppLocalization.string("Could Not Save Device"), isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button(AppLocalization.string("OK"), role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "") }
        }
    }

    /// The app-wide tailcat client key a host's allow list must name.
    private var tailcatClientKeySection: some View {
        Section {
            if let publicKey = model.tailcatClientPublicKey {
                Text(publicKey)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(3)
                    .textSelection(.enabled)
                Button(copiedClientKey
                    ? AppLocalization.string("Copied")
                    : AppLocalization.string("Copy Client Key")
                ) {
                    UIPasteboard.general.string = publicKey
                    copiedClientKey = true
                }
            }
            if let error = model.tailcatClientKeyError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button(AppLocalization.string("Regenerate Key"), role: .destructive) {
                confirmRegenerateClientKey = true
            }
            .confirmationDialog(
                AppLocalization.string("Regenerate the client key?"),
                isPresented: $confirmRegenerateClientKey,
                titleVisibility: .visible
            ) {
                Button(AppLocalization.string("Regenerate Key"), role: .destructive) {
                    model.regenerateTailcatClientKey()
                    copiedClientKey = false
                }
            } message: {
                Text(AppLocalization.string("Every host's allow.list must be updated with the new key, and all tailcat devices will reconnect."))
            }
        } header: {
            Text(AppLocalization.string("Client Key"))
        } footer: {
            Text(AppLocalization.string("If the host uses an allow list, add this key to allow.list in the folder from herdr plugin config-dir herdr.tailcat (one key per line), then run: herdr plugin action invoke herdr.tailcat.restart. All tailcat devices on this phone share this key."))
        }
        .onAppear { model.loadTailcatClientPublicKey() }
    }

    @ViewBuilder
    private var sshSections: some View {
        Section(AppLocalization.string("SSH Login")) {
            TextField(AppLocalization.string("Username"), text: $username)
                .textContentType(.username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Picker(AppLocalization.string("Authentication"), selection: $authMethod) {
                Text(AppLocalization.string("Device Key")).tag(MobileDevice.AuthMethod.deviceKey)
                Text(AppLocalization.string("Password")).tag(MobileDevice.AuthMethod.password)
            }
            if authMethod == .password {
                SecureField(AppLocalization.string("Password"), text: $password)
                    .textContentType(.password)
                if device?.authMethod == .password {
                    Text(AppLocalization.string("Leave blank to keep the saved password."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        Section {
            TextField(AppLocalization.string("Socket path (optional)"), text: $socketPath)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text(AppLocalization.string("Herdr Socket"))
        } footer: {
            Text(AppLocalization.string("Leave blank for the remote user's default socket. Otherwise enter its absolute path."))
        }
        if authMethod == .deviceKey {
            Section(AppLocalization.string("This Phone's Key")) {
                Text(model.deviceKeyAuthorizedLine)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(3)
                    .textSelection(.enabled)
                Button(copiedKey
                    ? AppLocalization.string("Copied")
                    : AppLocalization.string("Copy authorized_keys Line")
                ) {
                    UIPasteboard.general.string = model.deviceKeyAuthorizedLine
                    copiedKey = true
                }
                Text(AppLocalization.string("On the development machine, append this public key to ~/.ssh/authorized_keys."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                Text(AppLocalization.string("The password is stored in this device's Keychain and never leaves it except to log in over SSH."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
