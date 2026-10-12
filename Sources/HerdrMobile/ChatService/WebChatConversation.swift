import Foundation

/// Deployed web-ui 0.4.5 conversation schema, preserving future parts as readable content.
struct WebChatConversation: Codable, Equatable, Sendable {
    let source: String
    let historyID: String?
    let turns: [WebChatTurn]
    let cursor: String?
    let metadata: WebChatMetadata?
    var isStructured: Bool { source != "scrollback" && source.hasSuffix("-transcript") }
    enum CodingKeys: String, CodingKey { case source, turns, cursor, metadata; case historyID = "history_id" }
}
struct WebChatTurn: Codable, Equatable, Sendable {
    let role: String
    let ts: String?
    let endTS: String?
    let parts: [WebChatPart]
    enum CodingKeys: String, CodingKey { case role, ts, parts; case endTS = "end_ts" }
}
struct WebChatMetadata: Codable, Equatable, Sendable {
    let model: String?
    let reasoningEffort: String?
    let context: WebChatContext?
    enum CodingKeys: String, CodingKey { case model, context; case reasoningEffort = "reasoning_effort" }
}
struct WebChatContext: Codable, Equatable, Sendable { let used: Int; let window: Int? }
struct WebChatImage: Codable, Equatable, Sendable {
    let mediaType: String
    let ref: String
    enum CodingKeys: String, CodingKey { case ref; case mediaType = "media_type" }
}
struct WebChatSkill: Codable, Equatable, Sendable {
    let name: String
    let evidence: String
    let status: String
    let path: String?
}
struct WebChatTool: Codable, Equatable, Sendable {
    let name: String
    let summary: String
    let input: String
    let output: String
    let error: Bool?
    let outputRef: String?
    let outputSize: Int?
    let images: [WebChatImage]?
    let skill: WebChatSkill?
    enum CodingKeys: String, CodingKey {
        case name, summary, input, output, error, images, skill
        case outputRef = "output_ref", outputSize = "output_size"
    }
}
struct WebChatTaskResult: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let result: String
    let status: String
    let agent: String?
    let model: String?
    let durationMS: Int?
    let turns: Int?
    let toolCalls: Int?
    let tokens: Int?
    let resultCut: Bool?
    enum CodingKeys: String, CodingKey {
        case id, title, result, status, agent, model, turns, tokens
        case durationMS = "duration_ms", toolCalls = "tool_calls", resultCut = "result_cut"
    }
}

enum WebChatPart: Codable, Equatable, Sendable {
    case text(text: String, phase: String?)
    case thinking(String)
    case tool(WebChatTool)
    case image(WebChatImage)
    case compact(String)
    case notice(text: String, source: String?)
    case skill(WebChatSkill)
    case taskResult([WebChatTaskResult])
    case unknown(kind: String, description: String)

    private enum CodingKeys: String, CodingKey { case kind, text, phase, source, skill, tasks }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        switch kind {
        case "text": self = .text(text: try c.decode(String.self, forKey: .text), phase: try c.decodeIfPresent(String.self, forKey: .phase))
        case "thinking": self = .thinking(try c.decode(String.self, forKey: .text))
        case "compact": self = .compact(try c.decode(String.self, forKey: .text))
        case "notice": self = .notice(text: try c.decode(String.self, forKey: .text), source: try c.decodeIfPresent(String.self, forKey: .source))
        case "tool": self = .tool(try WebChatTool(from: decoder))
        case "image": self = .image(try WebChatImage(from: decoder))
        case "skill": self = .skill(try c.decode(WebChatSkill.self, forKey: .skill))
        case "task_result": self = .taskResult(try c.decode([WebChatTaskResult].self, forKey: .tasks))
        default:
            self = .unknown(kind: kind, description: (try? c.decode(String.self, forKey: .text)) ?? "Unsupported conversation content: \(kind)")
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text, let phase):
            try c.encode("text", forKey: .kind); try c.encode(text, forKey: .text); try c.encodeIfPresent(phase, forKey: .phase)
        case .thinking(let text): try c.encode("thinking", forKey: .kind); try c.encode(text, forKey: .text)
        case .compact(let text): try c.encode("compact", forKey: .kind); try c.encode(text, forKey: .text)
        case .notice(let text, let source):
            try c.encode("notice", forKey: .kind); try c.encode(text, forKey: .text); try c.encodeIfPresent(source, forKey: .source)
        case .tool(let tool): try c.encode("tool", forKey: .kind); try tool.encode(to: encoder)
        case .image(let image): try c.encode("image", forKey: .kind); try image.encode(to: encoder)
        case .skill(let skill): try c.encode("skill", forKey: .kind); try c.encode(skill, forKey: .skill)
        case .taskResult(let tasks): try c.encode("task_result", forKey: .kind); try c.encode(tasks, forKey: .tasks)
        case .unknown(let kind, let description): try c.encode(kind, forKey: .kind); try c.encode(description, forKey: .text)
        }
    }
}

enum WebChatPage: Hashable, Sendable { case latest, before(String), from(String), between(before: String, since: String) }
struct WebChatConversationResult: Sendable {
    let conversation: WebChatConversation
    let etag: String?
    let notModified: Bool
    let historyReplaced: Bool
}
struct WebChatImageData: Sendable { let data: Data; let contentType: String }
struct WebChatAttachment: Equatable, Sendable { let path: String; let name: String }

struct WebChatMachine: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let kind: String
    let state: String
    let enabled: Bool
    let snapshot: WebChatSnapshot?
}
struct WebChatSnapshot: Decodable, Sendable {
    let protocolVersion: Int
    let workspaces: [Space]
    let tabs: [Tab]
    let panes: [Pane]
    struct Space: Decodable, Sendable {
        let id: String
        enum CodingKeys: String, CodingKey { case id = "workspace_id" }
    }
    struct Tab: Decodable, Sendable {
        let id: String
        let spaceID: String
        enum CodingKeys: String, CodingKey { case id = "tab_id", spaceID = "workspace_id" }
    }
    struct Pane: Decodable, Sendable {
        let id: String
        let tabID: String
        let spaceID: String
        enum CodingKeys: String, CodingKey { case id = "pane_id", tabID = "tab_id", spaceID = "workspace_id" }
    }
    enum CodingKeys: String, CodingKey { case workspaces, tabs, panes; case protocolVersion = "protocol" }
    func contains(_ target: WebChatTarget) -> Bool {
        workspaces.contains { $0.id == target.spaceID }
        && tabs.contains { $0.id == target.tabID && $0.spaceID == target.spaceID }
        && panes.contains { $0.id == target.paneID && $0.tabID == target.tabID && $0.spaceID == target.spaceID }
    }
}
