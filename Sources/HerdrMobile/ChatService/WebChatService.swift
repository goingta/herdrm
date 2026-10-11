import Foundation

/// A single immutable service binding. Does not use Safari cookies, web page scripts, or SSH.
actor WebChatService {
    let configuration: WebChatConfiguration
    private let credential: WebChatCredential
    private let session: URLSession
    private var generation = UUID()
    private struct CacheKey: Hashable { let target: WebChatTarget; let page: WebChatPage }
    private var cache: [CacheKey: WebChatConversationResult] = [:]
    private var pending: [UUID: Task<(Data, URLResponse), Error>] = [:]
    private var requests: [CacheKey: UUID] = [:]

    init(configuration: WebChatConfiguration, credential: WebChatCredential, session: URLSession? = nil) {
        self.configuration = configuration
        self.credential = credential
        self.session = session ?? Self.isolatedSession()
    }

    func invalidate() {
        generation = UUID()
        cache.removeAll()
        requests.removeAll()
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
    }

    func machines() async throws -> [WebChatMachine] {
        struct Response: Decodable { let machines: [WebChatMachine] }
        let (data, _) = try await request(path: "api/machines")
        guard let list = try? JSONDecoder().decode(Response.self, from: data) else { throw WebChatError.incompatible }
        return list.machines
    }

    func conversation(for target: WebChatTarget, page: WebChatPage = .latest) async throws -> WebChatConversationResult {
        let epoch = generation
        let key = CacheKey(target: target, page: page)
        let serial = UUID()
        requests[key] = serial
        try await validate(target)
        guard generation == epoch, requests[key] == serial else { throw WebChatError.staleResponse }
        var query = [URLQueryItem(name: "pane_id", value: target.paneID)]
        switch page {
        case .latest: break
        case .before(let cursor): query.append(URLQueryItem(name: "before", value: cursor))
        case .from(let cursor): query.append(URLQueryItem(name: "from", value: cursor))
        }
        let previous = cache[key]
        let (data, response) = try await request(path: machinePath("pane/conversation"), query: query, etag: previous?.etag)
        guard generation == epoch, requests[key] == serial else { throw WebChatError.staleResponse }
        if response.statusCode == 304 {
            guard let previous else { throw WebChatError.invalidResponse }
            return WebChatConversationResult(conversation: previous.conversation, etag: previous.etag, notModified: true, historyReplaced: false)
        }
        guard let conversation = try? JSONDecoder().decode(WebChatConversation.self, from: data) else { throw WebChatError.incompatible }
        let oldHistory = cache.first { $0.key.target == target }?.value.conversation.historyID
        let replaced = oldHistory != nil && oldHistory != conversation.historyID
        if replaced { cache = cache.filter { $0.key.target != target } }
        let result = WebChatConversationResult(conversation: conversation, etag: response.value(forHTTPHeaderField: "ETag"), notModified: false, historyReplaced: replaced)
        cache[key] = result
        return result
    }

    private func validate(_ target: WebChatTarget) async throws {
        let machines = try await machines()
        guard let machine = machines.first(where: { $0.id == configuration.machineID }), machine.enabled,
              machine.state == "connected", let snapshot = machine.snapshot else { throw WebChatError.machineUnavailable }
        // Capability is the decoded exact identity schema, not an arbitrary maximum protocol version.
        guard snapshot.protocolVersion > 0 else { throw WebChatError.incompatible }
        guard snapshot.contains(target) else { throw WebChatError.targetMismatch }
    }

    private func machinePath(_ path: String) -> String {
        if configuration.machineID == "local" { return "api/\(path)" }
        let id = configuration.machineID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return "api/machines/\(id)/\(path)"
    }

    private func request(path: String, query: [URLQueryItem] = [], etag: String? = nil, method: String = "GET", body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        let epoch = generation
        let validated = try configuration.validated()
        guard var parts = URLComponents(url: validated.serviceURL, resolvingAgainstBaseURL: false) else { throw WebChatError.invalidConfiguration }
        parts.percentEncodedPath += path
        parts.queryItems = query.isEmpty ? nil : query
        guard let url = parts.url else { throw WebChatError.invalidConfiguration }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if method != "GET" { request.setValue("1", forHTTPHeaderField: "X-Herdr-Machine") }
        try credential.authorize(&request)
        let id = UUID()
        let task = Task { try await session.data(for: request) }
        pending[id] = task
        defer { pending.removeValue(forKey: id) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        } catch {
            if generation != epoch { throw WebChatError.staleResponse }
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw WebChatError.transport
        }
        guard generation == epoch else { throw WebChatError.staleResponse }
        guard let http = response as? HTTPURLResponse,
              http.url?.scheme == url.scheme, http.url?.host == url.host, http.url?.port == url.port else { throw WebChatError.unsafeRedirect }
        guard data.count <= 16 * 1024 * 1024 else { throw WebChatError.invalidResponse }
        if http.statusCode == 304 { return (data, http) }
        guard (200...299).contains(http.statusCode) else {
            switch http.statusCode {
            case 300...399: throw WebChatError.unsafeRedirect
            case 401: throw WebChatError.unauthorized
            case 403: throw WebChatError.forbidden
            case 409: throw WebChatError.historyChanged
            case 404, 405: throw WebChatError.incompatible
            default: throw WebChatError.server(status: http.statusCode, code: "request_failed")
            }
        }
        return (data, http)
    }

    private static func isolatedSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration, delegate: WebChatRedirectGuard(), delegateQueue: nil)
    }
}

/// Reject all redirects before resending any header/body, including credentials.
private final class WebChatRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum WebChatCredential: Codable, Sendable {
    case token(String)
    case pairedDevice(String)
    fileprivate func authorize(_ request: inout URLRequest) throws {
        switch self {
        case .token(let token):
            guard !token.isEmpty, !token.contains(where: { $0.isNewline || $0 == "\r" }) else { throw WebChatError.missingCredential }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .pairedDevice(let token):
            guard !token.isEmpty, let encoded = token.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { throw WebChatError.missingCredential }
            request.setValue("herdr_web_device=\(encoded)", forHTTPHeaderField: "Cookie")
        }
    }
}
