import CryptoKit
import Foundation
import Observation

struct ChatRenderProof: Equatable {
    let target: WebChatTarget
    let historyID: String
    let revision: String
    let completionRevision: UInt64
    var verifiedByCurrentPane = false
}

struct ChatVisibleReplyCandidate: Equatable {
    let target: WebChatTarget
    let historyID: String
    let revision: String
    let completionRevision: UInt64
    let text: String
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
    var onVisibleLatestReply: ((ChatVisibleReplyCandidate) -> Void)?
    private var issuedCandidate: ChatVisibleReplyCandidate?
    private var verifiedRevision: String?
    var onOpenURL: ((URL) -> Void)? {
        didSet { renderer.onOpenURL = onOpenURL }
    }
    private var active = false
    private var valid = true
    private var epoch = UUID()
    private var referenceTasks: [String: (UUID, Task<Void, Never>)] = [:]
    private var referenceOrder: [String] = []
    private var pollTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var completionRevision: UInt64 = 0
    private var theme = "dark"
    private var language = "en"
    private var textScale: Double = 1
    private var documentRevision = UUID().uuidString
    private var fresh = false
    private var olderTurns: [WebChatTurn] = []
    private var currentTurns: [WebChatTurn] = []
    private var olderCursor: String?
    private var hasLoadedOlder = false
    private(set) var historyLimitReached = false
    private var heldFrom: String?
    private var needsLatestReset = false
    private struct ReplyIdentity: Equatable { let history: String?; let fingerprint: String }
    private var completionBaseline: ReplyIdentity?
    private var completionBaselineHistory: String?
    private var hasCompletionBaseline = false
    private var completionProven = false
    private var agentStatus = "unknown"
    private var agentWorking = false
    private var workingBaseline: ReplyIdentity?
    private var workingBaselineHistory: String?
    private var hasWorkingBaseline = false

    /// Called synchronously before activity updates, so a final HTTP reply that arrives
    /// before the native done event still belongs to the preceding working cycle.
    func observeAgentStatus(_ status: String) {
        observeAgentWorking(status == "working")
        guard agentStatus != status else { return }
        agentStatus = status
        publish()
    }

    func observeAgentWorking(_ working: Bool) {
        if working && !agentWorking {
            workingBaseline = latestReply(conversation)
            workingBaselineHistory = conversation?.historyID
            hasWorkingBaseline = conversation != nil
        }
        agentWorking = working
    }

    /// The shell may call this only after a fresh, exact native pane verification.
    /// The renderer then rechecks visibility; an asynchronous verification cannot clear
    /// unread after a target/history/document change or after scrolling away.
    func acceptVerifiedCompletion(candidate: ChatVisibleReplyCandidate) {
        guard active, fresh, candidate == issuedCandidate, candidate.target == target,
              candidate.historyID == conversation?.historyID, candidate.revision == documentRevision,
              candidate.completionRevision == completionRevision else { return }
        verifiedRevision = documentRevision
        publish()
        renderer.requestVisibleProof()
    }

    private func visibleLatest(_ proof: ChatRendererProof) {
        guard active, fresh, proof.revision == documentRevision, let conversation,
              conversation.isStructured, let history = conversation.historyID, !history.isEmpty else { return }
        let text = conversation.turns.reversed().filter { $0.role == "assistant" }.lazy.compactMap { turn in
            turn.parts.reversed().compactMap { part -> String? in
                if case .text(let text, let phase) = part, (phase == nil || phase == "final_answer"), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
                return nil
            }.first
        }.first
        guard let text else { return }
        let candidate = ChatVisibleReplyCandidate(target: target, historyID: history, revision: documentRevision,
            completionRevision: completionRevision, text: String(text.suffix(2048)))
        issuedCandidate = candidate
        onVisibleLatestReply?(candidate)
    }

    init(target: WebChatTarget, service: WebChatService) {
        self.target = target
        self.service = service
        renderer.onReload = { [weak self] in
            guard let self else { return }
            self.fresh = false
            self.issuedCandidate = nil; self.verifiedRevision = nil
            self.documentRevision = UUID().uuidString
            self.publish()
            if self.active { self.refresh() }
        }
        renderer.onUnavailable = { [weak self] in
            self?.fresh = false
            self?.state = .failed(.transport)
            self?.pollTask?.cancel(); self?.pollTask = nil
            self?.fetchTask?.cancel(); self?.fetchTask = nil
            self?.epoch = UUID()
        }
        renderer.onLoadOlder = { [weak self] in self?.loadOlder() }
        renderer.onVisibleLatestReply = { [weak self] proof in self?.visibleLatest(proof) }
        renderer.onPresented = { [weak self] proof in self?.presented(proof) }
        renderer.onImage = { [weak self] ref, key, proof in self?.loadReference(ref, key: key, proof: proof, image: true) }
        renderer.onToolOutput = { [weak self] ref, key, proof in self?.loadReference(ref, key: key, proof: proof, image: false) }
    }

    func setActivity(visible: Bool, foreground: Bool, connectionValidated: Bool, completionRevision: UInt64) {
        if self.completionRevision != completionRevision {
            self.completionRevision = completionRevision
            completionBaseline = hasWorkingBaseline ? workingBaseline : latestReply(conversation)
            completionBaselineHistory = hasWorkingBaseline ? workingBaselineHistory : conversation?.historyID
            hasCompletionBaseline = hasWorkingBaseline || conversation != nil
            hasWorkingBaseline = false
            completionProven = false
            issuedCandidate = nil; verifiedRevision = nil
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
        issuedCandidate = nil; verifiedRevision = nil
        fresh = false
        publish()
        if next { startPolling() } else {
            epoch = UUID()
            pollTask?.cancel(); pollTask = nil
            fetchTask?.cancel(); fetchTask = nil
            for (_, task) in referenceTasks.values { task.cancel() }
            referenceTasks.removeAll(); referenceOrder.removeAll()
            isLoadingOlder = false
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
        if renderer.requiresReload { renderer.reloadRetainingContext() }
        if let task = fetchTask { await task.value; return }
        let expected = epoch
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetch(page: self.needsLatestReset ? .latest : self.heldFrom.map(WebChatPage.from) ?? .latest, expected: expected)
        }
        fetchTask = task
        await task.value
        if epoch == expected { fetchTask = nil }
    }

    func loadOlder() { Task { [weak self] in await self?.loadOlderNow() } }

    func loadOlderNow() async {
        if let task = fetchTask { await task.value }
        guard active, !isLoadingOlder, !historyLimitReached, let cursor = conversation?.cursor else { return }
        isLoadingOlder = true
        let expected = epoch
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.fetch(page: .before(cursor), expected: expected)
        }
        fetchTask = task
        await task.value
        if epoch == expected { isLoadingOlder = false; fetchTask = nil }
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
            var cursorInvalidated = false
            do { result = try await service.conversation(for: target, page: page) }
            catch WebChatError.historyChanged {
                cursorInvalidated = true
                result = try await service.conversation(for: target)
            }
            guard expected == epoch, active, !Task.isCancelled else { return }
            let incoming = result.conversation
            guard let encoded = try? JSONEncoder().encode(incoming), encoded.count <= 8 * 1024 * 1024 else { throw WebChatError.invalidResponse }
            let replaced = needsLatestReset || cursorInvalidated || result.historyReplaced || conversation.map { $0.historyID != incoming.historyID } == true
            let prepended: Bool
            if replaced {
                needsLatestReset = false
                olderTurns = []; currentTurns = []; heldFrom = nil
                olderCursor = incoming.cursor; hasLoadedOlder = false; historyLimitReached = false
            }
            if case .before = page, !replaced {
                olderTurns = incoming.turns + olderTurns
                olderCursor = incoming.cursor
                hasLoadedOlder = true
                prepended = true
            } else {
                if !replaced, let held = heldFrom, let start = incoming.cursor, held != start, incoming.isStructured {
                    let gap: [WebChatTurn]
                    do { gap = try await turnsBetween(held: held, start: start, history: incoming.historyID, expected: expected) }
                    catch { needsLatestReset = true; throw error }
                    guard expected == epoch, active, !Task.isCancelled else { return }
                    olderTurns += gap
                    hasLoadedOlder = true
                }
                currentTurns = incoming.turns
                heldFrom = incoming.cursor
                if !hasLoadedOlder { olderCursor = incoming.cursor }
                prepended = false
            }
            // Keep the latest page and at most 1000 total turns. The user sees an explicit
            // limit notice rather than an endlessly loading older-page control.
            if currentTurns.count > 1000 { historyLimitReached = true }
            currentTurns = Array(currentTurns.suffix(1000))
            let capacity = max(0, 1000 - currentTurns.count)
            if olderTurns.count > capacity {
                olderTurns = Array(olderTurns.suffix(capacity))
                historyLimitReached = true
            }
            // Bound retained text bytes as well as turn count. Eviction is explicit, and
            // latest turns are retained; no unbounded page accumulation crosses the bridge.
            while !olderTurns.isEmpty {
                let bytes = (try? JSONEncoder().encode(olderTurns + currentTurns).count) ?? Int.max
                if bytes <= 8 * 1024 * 1024 { break }
                olderTurns.removeFirst(max(1, olderTurns.count / 2))
                historyLimitReached = true
            }
            let latestMetadata: WebChatMetadata?
            if case .before = page, !replaced { latestMetadata = incoming.metadata ?? conversation?.metadata }
            else { latestMetadata = incoming.metadata }
            conversation = WebChatConversation(source: incoming.source, historyID: incoming.historyID,
                turns: olderTurns + currentTurns, cursor: historyLimitReached ? nil : olderCursor, metadata: latestMetadata)
            state = incoming.isStructured ? .ready : .degraded
            if completionRevision > 0 {
                let reply = latestReply(conversation)
                if replaced || !hasCompletionBaseline {
                    completionBaseline = reply
                    completionBaselineHistory = conversation?.historyID
                    hasCompletionBaseline = true
                    completionProven = false
                } else {
                    completionProven = reply != nil && reply?.history == completionBaselineHistory && reply != completionBaseline
                }
            }
            if agentWorking && !hasWorkingBaseline {
                workingBaseline = latestReply(conversation)
                workingBaselineHistory = conversation?.historyID
                hasWorkingBaseline = true
            }
            fresh = true
            documentRevision = UUID().uuidString
            issuedCandidate = nil; verifiedRevision = nil
            publish(prepended: prepended)
        } catch {
            guard expected == epoch, active, !Task.isCancelled else { return }
            fresh = false
            state = .failed((error as? WebChatError) ?? .transport)
            publish()
        }
    }

    private func turnsBetween(held: String, start: String, history: String?, expected: UUID) async throws -> [WebChatTurn] {
        var pages: [[WebChatTurn]] = []
        var before = start
        var visited: Set<String> = []
        var accumulatedBytes = 0
        for _ in 0..<32 {
            if before == held { return pages.flatMap { $0 } }
            guard visited.insert(before).inserted else { throw WebChatError.invalidResponse }
            let result = try await service.conversation(for: target, page: .between(before: before, since: held))
            guard expected == epoch, active, !Task.isCancelled else { throw CancellationError() }
            guard !result.historyReplaced, result.conversation.historyID == history,
                  let cursor = result.conversation.cursor else { throw WebChatError.historyChanged }
            accumulatedBytes += (try? JSONEncoder().encode(result.conversation.turns).count) ?? Int.max / 2
            guard accumulatedBytes <= 8 * 1024 * 1024 else { throw WebChatError.invalidResponse }
            pages.insert(result.conversation.turns, at: 0)
            guard pages.reduce(0, { $0 + $1.count }) <= 1000 else { throw WebChatError.invalidResponse }
            before = cursor
        }
        throw WebChatError.invalidResponse
    }

    private func key(_ turn: WebChatTurn) -> String {
        let source = turn.ts.map { turn.role + "|" + $0 } ?? String(decoding: (try? JSONEncoder().encode(turn)) ?? Data(), as: UTF8.self)
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func publish(prepended: Bool = false) {
        guard let conversation else { return }
        var occurrences: [String: Int] = [:]
        let turns = conversation.turns.map { turn in
            let identity = key(turn)
            let occurrence = occurrences[identity, default: 0]
            occurrences[identity] = occurrence + 1
            return ChatRenderTurn(role: turn.role, timestamp: turn.ts, parts: turn.parts.flatMap(renderParts), key: identity + ":" + String(occurrence), endTimestamp: turn.endTS, live: ["working", "blocked"].contains(agentStatus) && turn == conversation.turns.last, waiting: agentStatus == "blocked" && turn == conversation.turns.last)
        }
        var document = ChatRenderDocument(targetKey: target.presentationID.uuidString + ":" + target.paneID,
            historyID: conversation.historyID, revision: documentRevision, source: conversation.source, turns: turns)
        document.hasOlder = conversation.cursor != nil
        document.historyLimited = historyLimitReached
        document.prepended = prepended
        document.freshContent = fresh && active && conversation.isStructured
        document.readinessAllowed = document.freshContent && (completionRevision == 0 || completionProven || verifiedRevision == documentRevision)
        document.theme = theme; document.language = language; document.textScale = textScale
        document.labels = language == "zh" ? ["thinking":"思考过程", "worked":"已工作", "workedFor":"工作了", "working":"正在工作…", "waiting":"需要你回应", "copyMessage":"复制消息", "copy":"复制", "fullOutput":"加载完整输出", "image":"加载图片", "unknown":"暂不支持的内容", "older":"加载更早的消息", "empty":"暂无聊天记录", "degraded":"当前为终端回滚降级内容，服务未提供结构化聊天。", "limit":"为限制内存，较早的消息已释放。此页面最多保留最近 1000 条记录。"] : [:]
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
            return [.init(kind: "tool", name: tool.name, summary: tool.summary, input: tool.input, output: tool.output, ref: tool.outputRef, error: tool.error)]
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
                if case .text(let text, let phase) = part, (phase == nil || phase == "final_answer"), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
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
        guard referenceTasks[key] == nil else { return }
        if referenceOrder.count >= 4, let oldest = referenceOrder.first {
            referenceTasks.removeValue(forKey: oldest)?.1.cancel()
            referenceOrder.removeFirst()
        }
        let expected = epoch
        let taskID = UUID()
        referenceOrder.append(key)
        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.referenceTasks[key]?.0 == taskID {
                    self.referenceTasks.removeValue(forKey: key)
                    self.referenceOrder.removeAll { $0 == key }
                }
            }
            do {
                if image {
                    let result = try await service.image(for: target, ref: ref, historyID: history)
                    guard self.active, !Task.isCancelled, self.epoch == expected, self.conversation?.historyID == history else { return }
                    self.renderer.displayImage(result.data, contentType: result.contentType, key: key, ref: ref, proof: proof)
                } else {
                    let output = try await service.toolOutput(for: target, ref: ref, historyID: history)
                    guard self.active, !Task.isCancelled, self.epoch == expected, self.conversation?.historyID == history else { return }
                    self.renderer.displayToolOutput(output, key: key, ref: ref, proof: proof)
                }
            } catch {
                guard self.active, !Task.isCancelled, self.epoch == expected, self.conversation?.historyID == history else { return }
                self.renderer.displayReferenceError((error as? WebChatError)?.localizedDescription ?? "Content unavailable. Retry.", key: key, ref: ref, proof: proof)
            }
        }
        referenceTasks[key] = (taskID, task)
    }

    private func presented(_ proof: ChatRendererProof) {
        guard active, fresh, (completionRevision == 0 || completionProven || verifiedRevision == documentRevision), proof.revision == documentRevision, let conversation,
              conversation.isStructured, let history = conversation.historyID, !history.isEmpty,
              conversation.turns.contains(where: { $0.role == "assistant" && $0.parts.contains(where: { if case .text(let text, _) = $0 { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }; return false }) }) else { return }
        onPresented?(.init(target: target, historyID: history, revision: proof.revision, completionRevision: completionRevision, verifiedByCurrentPane: verifiedRevision == documentRevision))
    }
}
