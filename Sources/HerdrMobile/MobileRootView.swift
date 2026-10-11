import HerdrKit
import SwiftUI

/// One Space fills the phone. The native left drawer starts collapsed;
/// server tabs and a split-pane picker choose one existing terminal at a time.
struct MobileRootView: View {
    @Bindable var model: MobileAppModel
    var openChatURL: (URL) -> Void = { _ in }
    @State private var chatDevice: MobileDevice?
    @State private var drawerShown = false
    @State private var restorationHintVisible = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.agentTabVisible) private var rootVisible

    private var contentVisible: Bool { rootVisible && !drawerShown && chatDevice == nil && !model.showAddDevice && model.editingDevice == nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                ZStack(alignment: .leading) {
                    VStack(spacing: 0) {
                        if !model.workspaceTabs.isEmpty { tabStrip }
                        terminalDetail.frame(maxWidth: .infinity, maxHeight: .infinity)
                            .environment(\.agentTabVisible, contentVisible)
                            .allowsHitTesting(contentVisible)
                            .accessibilityHidden(!contentVisible)
                            .overlay(alignment: .top) {
                                if model.hasCurrentSnapshot, !model.selectedTransportReady, shouldShowRestorationHint {
                                    restorationBanner
                                }
                            }
                    }
                    .background(Theme.contentBackground)
                    .accessibilityHidden(drawerShown)
                    if drawerShown {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Button { drawerShown = false } label: { Color.black.opacity(0.28) }
                                    .buttonStyle(.plain).accessibilityLabel(AppLocalization.string("Close Sidebar"))
                                    .accessibilityIdentifier("spaces.drawer.close")
                                drawer.frame(width: min(340, proxy.size.width * 0.86))
                            }
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $chatDevice) { device in
            WebChatSettingsView(device: device) { configuration in
                try model.saveChatConfiguration(configuration, for: device.id)
            }
        }
        .sheet(isPresented: $model.showAddDevice) { DeviceEditorSheet(model: model) }
        .sheet(item: $model.editingDevice) { DeviceEditorSheet(model: model, device: $0) }
        .task { if model.selectedDeviceID != nil { model.connectSelected() } }
        .task(id: [model.selectedTransportReady, scenePhase == .active]) {
            restorationHintVisible = false
            guard !model.selectedTransportReady, scenePhase == .active else { return }
            // Input/read proof is gated immediately; quick healthy returns
            // finish validation before a restoration hint needs to appear.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, !model.selectedTransportReady, scenePhase == .active else { return }
            restorationHintVisible = true
        }
    }

    // A native custom bar preserves a real 44pt button boundary even on
    // system versions whose navigation-bar glass controls report 36pt frames.
    private var topBar: some View {
        HStack(spacing: 6) {
            Button { drawerShown.toggle() } label: {
                Image(systemName: "sidebar.left").font(.system(size: 20))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.string("Spaces"))
            .accessibilityIdentifier("spaces.drawer")
            HStack(spacing: 7) {
                if let kind = model.selectedAgent?.agent,
                   let resource = BrandIconLoader.agentIcon(for: kind) { BrandIcon(resource: resource, size: 22) }
                Text(model.selectedPaneTitle ?? "herdrm")
                    .font(.system(.headline, design: .default).weight(.semibold))
                    .lineLimit(1).truncationMode(.tail)
                    .accessibilityIdentifier("workspace.session.title")
            }
            .foregroundStyle(MobileReferenceTheme.strong)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                modeButton(.chat, symbol: "bubble", title: "Chat")
                modeButton(.terminal, symbol: "terminal", title: "Terminal")
            }
            .padding(3)
            .background(MobileReferenceTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(MobileReferenceTheme.border))
            Menu {
                Text(model.selectedPaneTitle ?? "herdrm")
                if let device = model.selectedDevice {
                    Text(device.name)
                    if let space = model.selectedSpace { Text(space.label) }
                    Button(AppLocalization.string("Chat Service")) { chatDevice = device }
                    Button(AppLocalization.string("Refresh")) {
                        if model.paneMode == .chat, let target = model.currentPromptTarget {
                            model.chatController(for: target)?.refresh()
                        } else { model.refreshTerminal() }
                    }
                    .accessibilityIdentifier("workspace.refresh")
                    .disabled(model.paneMode == .terminal ? !model.selectedTransportReady : model.currentPromptTarget.flatMap { model.chatController(for: $0) } == nil)
                    Text(connectionLabel)
                    Text(chatServiceStatus)
                    Button(AppLocalization.string("Edit Device")) { model.editingDevice = device }
                }
                Button(AppLocalization.string("Reconnect")) { model.resumeSelected() }
                Button(AppLocalization.string("Add Device")) { model.showAddDevice = true }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 20))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(AppLocalization.string("More"))
            .accessibilityIdentifier("workspace.more")
        }
        .foregroundStyle(MobileReferenceTheme.dim)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(MobileReferenceTheme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(MobileReferenceTheme.border).frame(height: 1) }
    }

    private func modeButton(_ mode: MobilePaneMode, symbol: String, title: String) -> some View {
        Button { model.selectMode(mode) } label: {
            Image(systemName: symbol).font(.system(size: 19))
                .foregroundStyle(model.paneMode == mode ? MobileReferenceTheme.accent : MobileReferenceTheme.dim)
                .frame(width: 44, height: 44)
                .background(model.paneMode == mode ? MobileReferenceTheme.input : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(mode == .chat && model.selectedAgent == nil)
        .accessibilityIdentifier("workspace.mode.\(mode.rawValue)")
        .accessibilityLabel(mode == .chat ? AppLocalization.string("Chat") : AppLocalization.string("Terminal"))
        .accessibilityAddTraits(model.paneMode == mode ? [.isSelected] : [])
    }

    private var drawer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    DeviceSwitcherMenu(model: model).buttonStyle(.plain)
                    Spacer()
                    Button { drawerShown = false } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(AppLocalization.string("Close Sidebar"))
                }
                if let device = model.selectedDevice {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(device.name, systemImage: "desktopcomputer").font(.subheadline.weight(.semibold))
                        if !device.isTailcat {
                            Text("\(device.username)@\(device.host):\(device.port)")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Label(connectionLabel, systemImage: connectionSymbol)
                            .font(.caption).foregroundStyle(connectionColor)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(Theme.hairline)
                }
                Text(AppLocalization.string("Spaces")).font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                ForEach(model.spaces) { space in
                    Button {
                        model.selectSpace(space.workspaceID)
                        drawerShown = false
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder").foregroundStyle(MobileReferenceTheme.dim)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(space.label).font(.body).foregroundStyle(Theme.text)
                                Text("#\(space.number)").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            SpaceAttentionGlyph(attention: model.attention(for: space.workspaceID))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(model.selectedSpaceID == space.workspaceID ? Theme.itemWashSelected : .clear,
                                    in: RoundedRectangle(cornerRadius: VisualMetrics.controlRadius))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("space.select.\(space.workspaceID)")
                    .accessibilityAddTraits(model.selectedSpaceID == space.workspaceID ? [.isSelected] : [])
                }
                if model.spaces.isEmpty { Text(connectionLabel).font(.callout).foregroundStyle(Theme.textSecondary) }
            }
            .padding(14)
        }
        .background(Theme.statusBarBackground)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.sidebarBorder).frame(width: 1) }
        .accessibilityIdentifier("spaces.sidebar")
    }

    private var tabStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(model.workspaceTabs) { tab in
                        HStack(spacing: 0) {
                            Button { model.selectTab(tab.id) } label: {
                                HStack(spacing: 7) {
                                    SpaceAttentionGlyph(attention: model.tabAttention(for: tab.id))
                                    Text(tab.label).font(.subheadline.weight(.medium)).lineLimit(1)
                                }
                                .padding(.horizontal, 12).frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("workspace.tab.\(tab.id)")
                            .accessibilityAddTraits(model.selectedTabID == tab.id ? [.isSelected] : [])
                            if model.selectedTabID == tab.id { panePicker(tabID: tab.id) }
                        }
                        .foregroundStyle(model.selectedTabID == tab.id ? MobileReferenceTheme.strong : MobileReferenceTheme.dim)
                        .padding(.vertical, 4)
                        .overlay(alignment: .bottom) {
                            if model.selectedTabID == tab.id { Rectangle().fill(MobileReferenceTheme.accent).frame(height: 2) }
                        }
                        .id(tab.id)
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollIndicators(.hidden)
            .task(id: "\(model.selectedSpaceID ?? "")/\(model.selectedTabID ?? "")/\(model.workspaceTabs.map(\.id).joined(separator: ","))") {
                await Task.yield()
                guard !Task.isCancelled, let selected = model.selectedTabID else { return }
                proxy.scrollTo(selected, anchor: .center)
            }
        }
        .background(MobileReferenceTheme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(MobileReferenceTheme.border).frame(height: 1) }
    }

    private func panePicker(tabID: String) -> some View {
        Menu {
            ForEach(Array(model.paneChoices(in: tabID).enumerated()), id: \.element.id) { index, pane in
                Button { model.selectPane(pane.id) } label: {
                    Label("\(index + 1). \(pane.title) · \(pane.agent?.agent ?? AppLocalization.string("Terminal"))", systemImage: pane.id == model.selectedAgentPaneID ? "checkmark" : "terminal")
                }
                .accessibilityIdentifier("workspace.pane.\(pane.id)")
                .accessibilityValue(pane.agent.map { agentStatusDescription($0.status, unread: model.isUnread($0)) } ?? AppLocalization.string("Terminal"))
                .accessibilityAddTraits(pane.id == model.selectedAgentPaneID ? [.isSelected] : [])
            }
        } label: {
            Image(systemName: "chevron.down").font(.system(size: 13))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(AppLocalization.string("Switch Pane"))
        .accessibilityIdentifier("workspace.panes")
    }

    @ViewBuilder
    private var terminalDetail: some View {
        if model.selectedDevice == nil {
            stateView("No Devices", detail: AppLocalization.string("Add a development machine running herdr to get started."), symbol: "desktopcomputer")
        } else if !model.hasCurrentSnapshot {
            if case .failed(let reason) = model.selectedConnectionState {
                stateView("Connection Failed", detail: reason, symbol: "exclamationmark.circle", retry: true)
            } else {
                stateView(model.selectedAgentPaneID == nil ? "Connecting…" : "Restoring Terminal…",
                          detail: model.selectedPaneTitle ?? model.selectedSpace?.label ?? "", symbol: "arrow.triangle.2.circlepath")
            }
        } else if model.selectedTargetUnavailable {
            stateView("Selected Terminal Unavailable", detail: [model.selectedPaneTitle,
                AppLocalization.string("The selected target is no longer available. Choose another existing pane, tab, or Space.")]
                .compactMap { $0 }.joined(separator: "\n"), symbol: "terminal")
        } else if model.selectedDevice?.isTailcat == true, model.selectedAgentPaneID != nil {
            stateView("No Terminal over Tailcat", detail: AppLocalization.string("This device's tunnel reaches herdr's control plane only. Use an SSH device to attach to a live terminal."), symbol: "terminal")
        } else if let agent = model.selectedAgent, let transport = model.selectedSession?.transport {
            if let target = model.currentPromptTarget {
                MobilePaneWorkspace(model: model, target: target, transport: transport, agent: agent,
                    configureChat: { chatDevice = model.selectedDevice }, openURL: openChatURL)
                    .id(MobilePaneContext(target))
            }
        } else if let pane = model.selectedTerminalPane, let terminalID = pane.terminalID, let transport = model.selectedSession?.transport {
            MobileTerminalScreen(transport: transport, target: .terminal(terminalID: terminalID), paneID: pane.paneID, title: model.terminalLabel(for: pane), transportReady: model.selectedTransportReady, refreshRevision: model.terminalRefreshRevision)
                .id("\(model.selectedDeviceID?.uuidString ?? "")-\(model.selectedSpaceID ?? "")-\(model.selectedTabID ?? "")-\(pane.paneID)-\(model.selectedSession?.presentationID.uuidString ?? "")")
        } else if model.spaces.isEmpty {
            stateView("No Spaces", detail: AppLocalization.string("No existing workspace is available on this development machine."), symbol: "folder")
        } else {
            stateView("No Existing Terminal", detail: AppLocalization.string("This tab has no available Agent or terminal. Choose another existing tab or Space."), symbol: "terminal")
        }
    }

    private var shouldShowRestorationHint: Bool {
        if case .failed = model.selectedConnectionState { return true }
        return restorationHintVisible
    }

    private var restorationBanner: some View {
        HStack(spacing: 8) {
            if case .failed(let reason) = model.selectedConnectionState {
                Image(systemName: "exclamationmark.circle")
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("Connection Failed")).font(.caption.weight(.semibold))
                    Text(reason).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                Button(AppLocalization.string("Reconnect")) { model.connectSelected() }.frame(minHeight: 44)
            } else {
                ProgressView().controlSize(.small)
                Text(AppLocalization.string("Restoring Terminal…")).font(.caption)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.statusBarBackground.opacity(0.96))
        .accessibilityIdentifier("workspace.connection-state")
    }

    private func stateView(_ title: String.LocalizationValue, detail: String, symbol: String, retry: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(AppLocalization.string(title), systemImage: symbol).font(.headline).foregroundStyle(Theme.text)
            if !detail.isEmpty { Text(detail).font(.callout).foregroundStyle(Theme.textSecondary) }
            if retry {
                Button(AppLocalization.string("Reconnect")) { model.connectSelected() }
                    .buttonStyle(.bordered).frame(minHeight: 44)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("workspace.connection-state")
    }

    private var chatServiceStatus: String {
        guard model.selectedDevice?.chatConfiguration != nil else { return AppLocalization.string("Chat Service: Not Configured") }
        guard let target = model.currentPromptTarget, let controller = model.chatController(for: target) else {
            return AppLocalization.string("Chat Service: Sign In Required")
        }
        switch controller.state {
        case .loading: return AppLocalization.string("Chat Service: Loading")
        case .ready: return AppLocalization.string(controller.renderer.document?.freshContent == true ? "Chat Service: Up to Date" : "Chat Service: Paused")
        case .degraded: return AppLocalization.string("Chat Service: Terminal Fallback")
        case .failed(let error): return AppLocalization.string("Chat Service") + ": " + error.localizedDescription
        }
    }

    private var connectionLabel: String {
        switch model.selectedConnectionState {
        case .idle: AppLocalization.string("Disconnected")
        case .connecting: AppLocalization.string("Connecting…")
        case .connected: model.selectedTransportReady ? AppLocalization.string("Connected") : AppLocalization.string("Restoring Terminal…")
        case .failed: AppLocalization.string("Connection Failed")
        }
    }
    private var connectionSymbol: String {
        switch model.selectedConnectionState { case .connected: model.selectedTransportReady ? "checkmark.circle" : "arrow.triangle.2.circlepath"; case .failed: "exclamationmark.circle"; default: "arrow.triangle.2.circlepath" }
    }
    private var connectionColor: Color {
        switch model.selectedConnectionState { case .connected: model.selectedTransportReady ? Theme.success : Theme.textSecondary; case .failed: Theme.danger; default: Theme.textSecondary }
    }
    private func composerDraft(paneID: String) -> Binding<String> {
        guard let deviceID = model.selectedDeviceID else { return .constant("") }
        return Binding(get: { model.agentDraft(paneID: paneID, deviceID: deviceID) },
                       set: { model.setAgentDraft($0, paneID: paneID, deviceID: deviceID) })
    }
}

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
                    .accessibilityIdentifier("device.select.\(candidate.id.uuidString)")
                }
                Divider()
                Button(AppLocalization.string("Add Device…")) { model.showAddDevice = true }
                    .accessibilityIdentifier("device.add.menu")
                if let selected = model.selectedDevice {
                    Button(AppLocalization.string("Edit Device…")) { model.editingDevice = selected }
                        .accessibilityIdentifier("device.edit")
                    Button(AppLocalization.string("Remove \(selected.name)"), role: .destructive) {
                        confirmRemove = true
                    }
                    .accessibilityIdentifier("device.remove")
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "desktopcomputer")
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.system(size: 18))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(AppLocalization.string("Development Machines"))
            }
            .accessibilityIdentifier("devices.menu")
            .confirmationDialog(AppLocalization.string("Remove this device?"), isPresented: $confirmRemove, titleVisibility: .visible) {
                Button(AppLocalization.string("Remove Device"), role: .destructive) {
                    do { try model.removeDevice(device) }
                    catch { removalError = error.localizedDescription }
                }
                .accessibilityIdentifier("device.remove.confirm")
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
    @State private var sshRoute: MobileDevice.SSHRoute = .direct
    @State private var gatewayHost = ""
    @State private var gatewayPort = "8080"
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
        _sshRoute = State(initialValue: device?.sshRoute ?? .direct)
        _gatewayHost = State(initialValue: device?.gatewayHost ?? "")
        _gatewayPort = State(initialValue: String(device?.gatewayPort ?? 8080))
    }

    private var validationError: String? {
        guard kind == .ssh else { return nil }
        do {
            let parsed = try parsedSSHPort()
            _ = try MobileDevice(name: name, host: host, port: parsed, username: username,
                sshRoute: sshRoute, gatewayHost: gatewayHost, gatewayPort: try parsedGatewayPort()).validated()
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

    private func parsedGatewayPort() throws -> UInt16 {
        guard sshRoute == .httpConnect else { return UInt16(gatewayPort) ?? 8080 }
        guard let parsed = UInt16(gatewayPort.trimmingCharacters(in: .whitespacesAndNewlines)), parsed > 0 else {
            throw MobileDeviceError.invalidGatewayPort
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
                        .accessibilityIdentifier("device.name")
                    if kind == .ssh {
                        TextField(AppLocalization.string("Host or IP"), text: $host)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("device.host")
                        TextField(AppLocalization.string("Port"), text: $port)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("device.port")
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
                    Section { Text(validationError).foregroundStyle(Theme.danger).font(.footnote) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.contentBackground)
            .foregroundStyle(Theme.text)
            .navigationTitle(device == nil ? AppLocalization.string("Add Device") : AppLocalization.string("Edit Device"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                        .accessibilityIdentifier("device.cancel")
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
                                    edited.sshRoute = sshRoute
                                    edited.gatewayHost = gatewayHost
                                    edited.gatewayPort = try parsedGatewayPort()
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
                                    socketPath: socketPath,
                                    sshRoute: sshRoute,
                                    gatewayHost: gatewayHost,
                                    gatewayPort: try parsedGatewayPort()
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
                    .accessibilityIdentifier("device.save")
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
                    .foregroundStyle(Theme.danger)
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
        Section(AppLocalization.string("SSH Network")) {
            Picker(AppLocalization.string("SSH Route"), selection: $sshRoute) {
                Text(AppLocalization.string("Direct Connection")).tag(MobileDevice.SSHRoute.direct)
                Text(AppLocalization.string("HTTP CONNECT")).tag(MobileDevice.SSHRoute.httpConnect)
            }
            if sshRoute == .httpConnect {
                TextField(AppLocalization.string("Gateway host or IP"), text: $gatewayHost)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField(AppLocalization.string("Gateway port"), text: $gatewayPort)
                    .keyboardType(.numberPad)
                Text(AppLocalization.string("The gateway opens a tunnel to the SSH host above. SSH still verifies and authenticates the development machine."))
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
        }
        Section(AppLocalization.string("SSH Login")) {
            TextField(AppLocalization.string("Username"), text: $username)
                .textContentType(.username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("device.username")
            Picker(AppLocalization.string("Authentication"), selection: $authMethod) {
                Text(AppLocalization.string("Device Key")).tag(MobileDevice.AuthMethod.deviceKey)
                Text(AppLocalization.string("Password")).tag(MobileDevice.AuthMethod.password)
            }
            if authMethod == .password {
                SecureField(AppLocalization.string("Password"), text: $password)
                    .textContentType(.password)
                if device?.authMethod == .password {
                    Text(AppLocalization.string("Leave blank to keep the saved password."))
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
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
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            Section {
                Text(AppLocalization.string("The password is stored in this device's Keychain and never leaves it except to log in over SSH."))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
