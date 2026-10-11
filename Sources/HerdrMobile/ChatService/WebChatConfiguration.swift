import Foundation

/// Public binding only. Secrets are stored separately using credentialID.
struct WebChatConfiguration: Codable, Hashable, Sendable {
    let serviceURL: URL
    let machineID: String
    let credentialID: UUID

    init(serviceURL: String, machineID: String, credentialID: UUID = UUID()) throws {
        guard var components = URLComponents(string: serviceURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true,
              !machineID.isEmpty, !machineID.contains(where: { $0.isWhitespace || $0.isNewline })
        else { throw WebChatError.invalidConfiguration }
        components.scheme = components.scheme?.lowercased()
        components.host = host.lowercased()
        // A service can be mounted below a proxy prefix; keep that prefix.
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = components.path.isEmpty ? "/" : "/\(components.path)/"
        guard let url = components.url else { throw WebChatError.invalidConfiguration }
        self.serviceURL = url
        self.machineID = machineID
        self.credentialID = credentialID
    }

    func validated() throws -> WebChatConfiguration {
        try WebChatConfiguration(serviceURL: serviceURL.absoluteString, machineID: machineID, credentialID: credentialID)
    }
}

struct WebChatTarget: Hashable, Sendable {
    let nativeDeviceID: UUID
    let presentationID: UUID
    let spaceID: String
    let tabID: String
    let paneID: String
}

enum WebChatError: Error, LocalizedError, Equatable {
    case invalidConfiguration, missingCredential, unauthorized, forbidden, incompatible
    case machineUnavailable, targetMismatch, historyChanged, staleResponse
    case attachmentTooLarge, invalidAttachment, unsafeRedirect, invalidResponse
    case server(status: Int, code: String)
    case transport

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Enter an HTTP(S) service address without credentials, query, or fragment, and choose its machine."
        case .missingCredential: return "Sign in to the chat service with its token or pairing code."
        case .unauthorized: return "Chat service sign-in expired or was refused. Sign in again."
        case .forbidden: return "The chat service denied this operation. Check this credential's access."
        case .incompatible: return "This chat service does not support the required conversation protocol."
        case .machineUnavailable: return "The bound chat machine is disconnected or unavailable."
        case .targetMismatch: return "The selected Space, Tab, and pane do not belong to the bound chat machine. Check the binding."
        case .historyChanged: return "The conversation history changed. Refresh before loading older content."
        case .staleResponse: return "The chat target changed. This response was discarded."
        case .attachmentTooLarge: return "Choose a file no larger than 8 MiB."
        case .invalidAttachment: return "The attachment is empty or its file type/name is invalid."
        case .unsafeRedirect: return "The chat service redirected the request. Its credential was not forwarded."
        case .invalidResponse: return "The chat service returned an unreadable response."
        case .server(let status, let code): return "Chat service error (HTTP \(status), \(code))."
        case .transport: return "The chat service could not be reached. Check its address and network, then retry."
        }
    }
}
