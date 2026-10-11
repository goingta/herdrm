import CryptoKit
import Foundation
import Observation

struct ChatRenderProof: Equatable {
    let target: WebChatTarget
    let historyID: String
    let revision: String
    let completionRevision: UInt64
}

enum ChatTranscriptState: Equatable {
    case loading, ready, degraded, failed(WebChatError)
}

/// Owns one immutable target and its retained document. It never manages SSH or user input.
@MainActor @Observable
final class ChatTranscriptController {
    let target: WebChatTarget
    let service: WebChatService
    let renderer = ChatTranscriptRenderer()
    private(set) var conversation: WebChatConversation?
    private(set) var state: ChatTranscriptState = .loading
    private(set) var isLoadingOlder = false
    var metadata: WebChatMetadata? { conversation?.metadata }
    var onPresented: ((ChatRenderProof) -> Void)?
    var onOpenURL: ((URL) -> Void)? {
        didSet { renderer.onOpenURL = onOpenURL }
    }
    private var active = false
    private var valid = true
    private var epoch = UUID()
    private var pollTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var completionRevision: UInt64 = 0
    private var theme = "dark"
    private var language = "en"
    private var textScale: Double = 1
    private var documentRevision = UUID().uuidString
    private var fresh = false
    private struct ReplyIdentity: Equatable { let history: String?; let fingerprint: String }
    private var completionBaseline: ReplyIdentity?
    private var hasCompletionBaseline = false
    private var completionProven = false

    init(target: WebChatTarget, service: WebChatService) {
        self.target = target
        self.service = service
        renderer.onLoadOlder = { [weak self] in self?.loadOlder() }
        renderer.onPresented = { [weak self] proof in self?.presented(proof) }
        renderer.onImage = { [weak self] ref, key, proof in self?.loadReference(ref, key: key, proof: proof, image: true) }
        renderer.onToolOutput = { [weak self] ref, key, proof in self?.loadReference(ref, key: key, proof: proof, image: false) }
    }

    func setActivity(visible: Bool, foreground: Bool, connectionValidated: Bool, completionRevision: UInt64) {
        if self.completionRevision != completionRevision {
            self.completionRevision = completionRevision
            completionBaseline = latestReply(conversation)
            hasCompletionBaseline = conversation != nil
            completionProven = false
            fresh = false
            epoch = UUID()
            fetchTask?.cancel(); fetchTask = nil
            publish()
            if active { refresh() }
        }
        let next = visible && foreground && connectionValidated && valid
        guard active != next else { return }
        active = next
        renderer.setVisible(next)
        fresh = false
        publish()
        if next { startPolling() } else {
            epoch = UUID()
            pollTask?.cancel(); pollTask = nil
            fetchTask?.cancel(); fetchTask = nil
        }
    }

    func setAppearance(theme: String, language: String, textScale: Double) {
        self.theme = theme == "light" ? "light" : "dark"
        self.language = language == "zh" ? "zh" : "en"
        self.textScale = min(3, max(1, textScale))
        publish()
    }

    func refresh() { Task { [weak self] in await self?.refreshNow() } }

    func refreshNow() async {
        guard active else { return }
        if let task = fetchTask { await task.value; return }
        let expected = epoch
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetch(page: self.conversation?.cursor.map(WebChatPage.from) ?? .latest, expected: expected)
        }
        fetchTask = task
        await task.value
        if epoch == expected { fetchTask = nil }
    }

    func loadOlder() { Task { [weak self] in await self?.loadOlderNow() } }

    func loadOlderNow() async {
        guard active, !isLoadingOlder, let cursor = conversation?.cursor else { return }
        isLoadingOlder = true
        let expected = epoch
        await fetch(page: .before(cursor), expected: expected)
        if epoch == expected { isLoadingOlder = false }
    }

    func invalidate() {
        valid = false
        setActivity(visible: false, foreground: false, connectionValidated: false, completionRevision: completionRevision)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.active else { return }
                await self.refreshNow()
                if case .failed(.unauthorized) = self.state { return }
                if case .failed(.forbidden) = self.state { return }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    private func fetch(page: WebChatPage, expected: UUID) async {
        do {
            let result: WebChatConversationResult
            do { result = try await service.conversation(for: target, page: page) }
            catch WebChatError.historyChanged { result = try await service.conversation(for: target) }
            guard expected == epoch, active, !Task.isCancelled else { return }
            let incoming = result.conversation
            let replaced = result.historyReplaced || conversation.map { $0.historyID != incoming.historyID } == true
            let turns: [WebChatTurn]
            let cursor: String?
            let prepended: Bool
            if case .before = page, !replaced, let previous = conversation {
                turns = merge(incoming.turns, previous.turns)
                cursor = incoming.cursor
                prepended = true
            } else if !replaced, let previous = conversation {
                turns = merge(previous.turns, incoming.turns)
                cursor = previous.cursor
                prepended = false
            } else {
                turns = incoming.turns
                cursor = incoming.cursor
                prepended = false
            }
            let bounded = Array(turns.suffix(1000))
            conversation = WebChatConversation(source: incoming.source, historyID: incoming.historyID, turns: bounded,
                cursor: turns.count > 1000 ? incoming.cursor : cursor, metadata: incoming.metadata)
            state = incoming.isStructured ? .ready : .degraded
            if completionRevision > 0 {
                let reply = latestReply(conversation)
                if replaced || !hasCompletionBaseline {
                    completionBaseline = reply
                    hasCompletionBaseline = true
                    completionProven = false
                } else if let reply, reply.history == completionBaseline?.history, reply != completionBaseline {
                    completionProven = true
                }
            }
            fresh = true
            documentRevision = UUID().uuidString
            publish(prepended: prepended)
        } catch {
            guard expected == epoch, active, !Task.isCancelled else { return }
            fresh = false
            state = .failed((error as? WebChatError) ?? .transport)
            publish()
        }
    }

    private func merge(_ older: [WebChatTurn], _ newer: [WebChatTurn]) -> [WebChatTurn] {
        var values = older
        var indices = Dictionary(older.enumerated().map { (key($0.element), $0.offset) }, uniquingKeysWith: { first, _ in first })
        for turn in newer {
            let identity = key(turn)
            if let index = indices[identity] { values[index] = turn }
            else { indices[identity] = values.count; values.append(turn) }
        }
        return values
    }

    private func key(_ turn: WebChatTurn) -> String {
        let source = turn.ts.map { turn.role + "|" + $0 } ?? String(decoding: (try? JSONEncoder().encode(turn)) ?? Data(), as: UTF8.self)
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func publish(prepended: Bool = false) {
        guard let conversation else { return }
        let turns = conversation.turns.map { turn in
            ChatRenderTurn(role: turn.role, timestamp: turn.ts, parts: turn.parts.flatMap(renderParts), key: key(turn))
        }
        var document = ChatRenderDocument(targetKey: target.presentationID.uuidString + ":" + target.paneID,
            historyID: conversation.historyID, revision: documentRevision, source: conversation.source, turns: turns)
        document.hasOlder = conversation.cursor != nil
        document.prepended = prepended
        document.readinessAllowed = fresh && active && conversation.isStructured && (completionRevision == 0 || completionProven)
        document.theme = theme; document.language = language; document.textScale = textScale
        document.labels = language == "zh" ? ["thinking":"思考过程", "copy":"复制", "fullOutput":"加载完整输出", "image":"加载图片", "unknown":"暂不支持的内容", "older":"加载更早的消息", "empty":"暂无聊天记录", "degraded":"当前为终端回滚降级内容，服务未提供结构化聊天。"] : [:]
        // Bound display memory independently of the HTTP boundary. Never send an oversized
        // transcript across the native bridge; retain the previous readable page on failure.
        guard let data = try? JSONEncoder().encode(document), data.count <= 8 * 1024 * 1024 else {
            fresh = false; state = .failed(.invalidResponse); return
        }
        renderer.present(document)
    }

    private func renderParts(_ part: WebChatPart) -> [ChatRenderPart] {
        switch part {
        case .text(let text, let phase): return [.init(kind: "text", text: text, phase: phase)]
        case .thinking(let text): return [.init(kind: "thinking", text: text)]
        case .tool(let tool):
            return [.init(kind: "tool", name: tool.name, summary: tool.summary, input: tool.input, output: tool.output, ref: tool.outputRef)]
                + (tool.images ?? []).map { .init(kind: "image", ref: $0.ref) }
        case .image(let image): return [.init(kind: "image", ref: image.ref)]
        case .compact(let text): return [.init(kind: "compact", text: text)]
        case .notice(let text, let source): return [.init(kind: "notice", text: text, name: source)]
        case .skill(let skill): return [.init(kind: "skill", text: skill.evidence + " · " + skill.status, name: skill.name)]
        case .taskResult(let tasks): return tasks.map { .init(kind: "task_result", text: $0.result, name: $0.title + " · " + $0.status) }
        case .unknown(let kind, let description): return [.init(kind: kind, text: description)]
        }
    }

    private func latestReply(_ conversation: WebChatConversation?) -> ReplyIdentity? {
        guard let conversation, conversation.isStructured else { return nil }
        for turn in conversation.turns.reversed() where turn.role == "assistant" {
            let text = turn.parts.compactMap { part -> String? in
                if case .text(let text, let phase) = part, phase != "commentary", !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
                return nil
            }.joined(separator: "\n\n")
            if !text.isEmpty {
                let fingerprint = SHA256.hash(data: Data((key(turn) + "|" + text).utf8)).map { String(format: "%02x", $0) }.joined()
                return ReplyIdentity(history: conversation.historyID, fingerprint: fingerprint)
            }
        }
        return nil
    }

    private func loadReference(_ ref: String, key: String, proof: ChatRendererProof, image: Bool) {
        guard active, let history = conversation?.historyID, history == proof.historyID else { return }
        let expected = epoch
        Task { [weak self] in
            guard let self else { return }
            do {
                if image {
                    let result = try await service.image(for: target, ref: ref, historyID: history)
                    guard self.active, self.epoch == expected, self.conversation?.historyID == history else { return }
                    self.renderer.displayImage(result.data, contentType: result.contentType, key: key, proof: proof)
                } else {
                    let output = try await service.toolOutput(for: target, ref: ref, historyID: history)
                    guard self.active, self.epoch == expected, self.conversation?.historyID == history else { return }
                    self.renderer.displayToolOutput(output, key: key, proof: proof)
                }
            } catch {
                guard self.active, self.epoch == expected, self.conversation?.historyID == history else { return }
                self.renderer.displayReferenceError((error as? WebChatError)?.localizedDescription ?? "Content unavailable. Retry.", key: key, proof: proof)
            }
        }
    }

    private func presented(_ proof: ChatRendererProof) {
        guard active, fresh, (completionRevision == 0 || completionProven), proof.revision == documentRevision, let conversation,
              conversation.isStructured, let history = conversation.historyID, !history.isEmpty,
              conversation.turns.contains(where: { $0.role == "assistant" && $0.parts.contains(where: { if case .text(let text, _) = $0 { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }; return false }) }) else { return }
        onPresented?(.init(target: target, historyID: history, revision: proof.revision, completionRevision: completionRevision))
    }
}
