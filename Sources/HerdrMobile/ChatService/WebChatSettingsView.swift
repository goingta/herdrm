import SwiftUI
import Observation

/// The public configuration workflow is independent of the selected native SSH connection.
@MainActor @Observable
final class WebChatSettingsModel {
    enum LoginMethod: String, CaseIterable { case token, pairing }
    let device: MobileDevice
    var serviceAddress: String {
        didSet {
            guard oldValue != serviceAddress else { return }
            generation = UUID()
            credential = nil
            authenticatedAddress = nil
            machines = []
            machineID = ""
            isLoading = false
            token = ""
            pairingCode = ""
        }
    }
    var machineID: String
    var loginMethod: LoginMethod = .token
    var token = ""
    var pairingCode = ""
    private(set) var machines: [WebChatMachine] = []
    private(set) var isLoading = false
    private(set) var authenticatedAddress: URL?
    private var credential: WebChatCredential?
    private let session: URLSession?
    private var generation = UUID()

    init(device: MobileDevice, session: URLSession? = nil) {
        self.device = device
        self.session = session
        serviceAddress = device.chatConfiguration?.serviceURL.absoluteString ?? ""
        machineID = device.chatConfiguration?.machineID ?? ""
        if let existing = device.chatConfiguration {
            credential = WebChatSecretStore.credential(for: existing, nativeDeviceID: device.id)
            if case .pairedDevice? = credential { loginMethod = .pairing }
        }
    }

    var hasSavedCredential: Bool { credential != nil }
    var canSave: Bool {
        credential != nil && authenticatedAddress != nil && machines.contains { $0.id == machineID }
    }

    func signIn() async throws {
        let epoch = generation
        let configuration = try WebChatConfiguration(serviceURL: serviceAddress, machineID: "configuration")
        let savedCredential = credential
        credential = nil
        authenticatedAddress = nil
        isLoading = true
        defer { if generation == epoch { isLoading = false } }
        let candidate: WebChatCredential
        switch loginMethod {
        case .token:
            if !token.isEmpty { candidate = .token(token) }
            else if let savedCredential { candidate = savedCredential }
            else { throw WebChatError.missingCredential }
        case .pairing:
            if !pairingCode.isEmpty {
                candidate = try await WebChatService.pairedCredential(configuration: configuration, code: pairingCode, label: device.name, session: session)
            } else if let savedCredential { candidate = savedCredential }
            else { throw WebChatError.missingCredential }
        }
        let service = WebChatService(configuration: configuration, credential: candidate, session: session)
        let loaded = try await service.machines()
        guard generation == epoch, !Task.isCancelled else { throw WebChatError.staleResponse }
        guard !loaded.isEmpty else { throw WebChatError.incompatible }
        credential = candidate
        authenticatedAddress = configuration.serviceURL
        machines = loaded
        // Preserve an explicit previous selection only if that identity still exists.
        if !loaded.contains(where: { $0.id == machineID }) { machineID = "" }
        token = ""
        pairingCode = ""
    }

    @discardableResult
    func save(using onSave: (WebChatConfiguration?) throws -> Void) throws -> WebChatConfiguration {
        guard canSave, let credential, let authenticatedAddress else { throw WebChatError.missingCredential }
        var candidate = try WebChatConfiguration(serviceURL: serviceAddress, machineID: machineID)
        guard candidate.serviceURL == authenticatedAddress else { throw WebChatError.staleResponse }
        if let previous = device.chatConfiguration, previous.serviceURL == candidate.serviceURL, previous.machineID == candidate.machineID {
            candidate = try WebChatConfiguration(serviceURL: serviceAddress, machineID: machineID, credentialID: previous.credentialID)
        }
        let previousCredential = WebChatSecretStore.credential(for: candidate, nativeDeviceID: device.id)
        let oldCredential = device.chatConfiguration.flatMap { WebChatSecretStore.credential(for: $0, nativeDeviceID: device.id) }
        try WebChatSecretStore.setCredential(credential, for: candidate, nativeDeviceID: device.id)
        do { try onSave(candidate) }
        catch {
            // The public profile save can fail even after reauth. Restore same-ID credentials too.
            if let previousCredential { try WebChatSecretStore.setCredential(previousCredential, for: candidate, nativeDeviceID: device.id) }
            else { try WebChatSecretStore.removeCredential(for: candidate, nativeDeviceID: device.id) }
            if let previous = device.chatConfiguration, previous != candidate, let oldCredential {
                try WebChatSecretStore.setCredential(oldCredential, for: previous, nativeDeviceID: device.id)
            }
            throw error
        }
        if let previous = device.chatConfiguration, previous != candidate {
            try WebChatSecretStore.removeCredential(for: previous, nativeDeviceID: device.id)
        }
        return candidate
    }

    func remove(using onSave: (WebChatConfiguration?) throws -> Void) throws {
        guard let previous = device.chatConfiguration else { return }
        let oldCredential = WebChatSecretStore.credential(for: previous, nativeDeviceID: device.id)
        try WebChatSecretStore.removeCredential(for: previous, nativeDeviceID: device.id)
        do { try onSave(nil) }
        catch {
            if let oldCredential { try WebChatSecretStore.setCredential(oldCredential, for: previous, nativeDeviceID: device.id) }
            throw error
        }
        clearSensitiveInput()
    }

    func clearSensitiveInput() {
        generation = UUID()
        token = ""
        pairingCode = ""
        credential = nil
        isLoading = false
    }
}

@MainActor
struct WebChatSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: WebChatSettingsModel
    @State private var errorMessage: String?
    @State private var authenticationTask: Task<Void, Never>?
    private let onSave: (WebChatConfiguration?) throws -> Void

    init(device: MobileDevice, onSave: @escaping (WebChatConfiguration?) throws -> Void) {
        _model = State(initialValue: WebChatSettingsModel(device: device))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(AppLocalization.string("Service address"), text: $model.serviceAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .accessibilityIdentifier("chat.service.address")
                } header: { Text(AppLocalization.string("Chat service")) }
                footer: { Text(AppLocalization.string("SSH authentication and chat service sign-in are independent.")) }

                Section {
                    Picker(AppLocalization.string("Sign in with"), selection: $model.loginMethod) {
                        Text(AppLocalization.string("Service token")).tag(WebChatSettingsModel.LoginMethod.token)
                        Text(AppLocalization.string("Pairing code")).tag(WebChatSettingsModel.LoginMethod.pairing)
                    }
                    if model.loginMethod == .token {
                        SecureField(AppLocalization.string("Service token"), text: $model.token)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("chat.service.token")
                    } else {
                        SecureField(AppLocalization.string("Six-digit pairing code"), text: $model.pairingCode)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("chat.service.pairing")
                        Text(AppLocalization.string("Create a pairing code in your authenticated herdr-web-ui, then enter it here."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        authenticationTask?.cancel()
                        errorMessage = nil
                        authenticationTask = Task {
                            do { try await model.signIn() }
                            catch is CancellationError {}
                            catch { if !Task.isCancelled { show(error) } }
                        }
                    } label: {
                        HStack {
                            Text(AppLocalization.string("Sign in and load machines"))
                            if model.isLoading { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(model.isLoading)
                    .accessibilityIdentifier("chat.service.authenticate")
                }.privacySensitive()

                if !model.machines.isEmpty {
                    Section {
                        Picker(AppLocalization.string("Service machine"), selection: $model.machineID) {
                            Text(AppLocalization.string("Choose a machine")).tag("")
                            ForEach(model.machines) { machine in
                                Text("\(machine.name) · \(machine.id)").tag(machine.id)
                            }
                        }.accessibilityIdentifier("chat.service.machine")
                        Text(AppLocalization.string("The selected machine must contain this development machine's exact Space, Tab and pane identities."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red).accessibilityIdentifier("chat.service.error") } }
                if model.device.chatConfiguration != nil {
                    Section {
                        Button(AppLocalization.string("Remove chat binding"), role: .destructive) {
                            do { try model.remove(using: onSave); dismiss() } catch { show(error) }
                        }.accessibilityIdentifier("chat.service.remove")
                    }
                }
            }
            .navigationTitle(AppLocalization.string("Chat service"))
            .navigationBarTitleDisplayMode(.inline)
            .tint(Theme.accent)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLocalization.string("Save")) {
                        do { try model.save(using: onSave); dismiss() } catch { show(error) }
                    }.disabled(!model.canSave || model.isLoading).accessibilityIdentifier("chat.service.save")
                }
            }
            .task {
                if model.hasSavedCredential {
                    do { try await model.signIn() } catch { if !Task.isCancelled { show(error) } }
                }
            }
            .onDisappear { authenticationTask?.cancel(); model.clearSensitiveInput() }
        }
    }

    private func show(_ error: Error) {
        // Only curated product errors reach the form; HTTP bodies and credential echoes never do.
        if let error = error as? WebChatError { errorMessage = error.errorDescription }
        else if let error = error as? MobileDeviceError { errorMessage = error.errorDescription }
        else { errorMessage = AppLocalization.string("Could not save the chat service configuration. Try again.") }
    }
}
