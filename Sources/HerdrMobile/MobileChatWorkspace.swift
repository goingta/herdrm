import HerdrKit
import SwiftUI

/// Mode changes retain both the already-open native terminal and the chat document.
/// An Agent's initial chat does not attach a competing terminal merely to be hidden.
struct MobilePaneWorkspace: View {
    @Bindable var model: MobileAppModel
    let target: MobilePromptTarget
    let transport: MobileTransport
    let agent: AgentInfo
    let configureChat: () -> Void
    let openURL: (URL) -> Void
    @State private var terminalWasOpened = false
    @Environment(\.agentTabVisible) private var rootVisible

    private var terminalVisible: Bool { rootVisible && model.paneMode == .terminal }
    private var draft: Binding<String> {
        Binding(get: { model.agentDraft(paneID: target.paneID, deviceID: target.deviceID) },
                set: { model.setAgentDraft($0, paneID: target.paneID, deviceID: target.deviceID) })
    }

    var body: some View {
        ZStack {
            if terminalWasOpened {
                MobileTerminalScreen(transport: transport, target: .agent(paneID: target.paneID),
                    paneID: target.paneID, title: agent.title(tabLabel: model.tabLabel(for: agent)), composerDraft: draft,
                    readState: model.agentReadState, unreadKey: AgentUnreadKey(deviceID: target.deviceID, paneID: target.paneID),
                    onReadStateChanged: { model.terminalReadStateChanged() }, transportReady: model.selectedTransportReady, submitPrompt: { await model.submitPrompt(target: target) }, refreshRevision: model.terminalRefreshRevision)
                    .environment(\.agentTabVisible, terminalVisible)
                    .opacity(model.paneMode == .terminal ? 1 : 0)
                    .allowsHitTesting(terminalVisible).accessibilityHidden(!terminalVisible)
                    .zIndex(model.paneMode == .terminal ? 1 : 0)
            }
            MobileChatWorkspace(model: model, target: target, configureChat: configureChat, openURL: openURL)
                .id(ChatViewIdentity(configuration: model.selectedDevice?.chatConfiguration,
                    generation: model.chatBindingGeneration(for: target.deviceID)))
                .opacity(model.paneMode == .chat ? 1 : 0)
                .allowsHitTesting(rootVisible && model.paneMode == .chat)
                .accessibilityHidden(!(rootVisible && model.paneMode == .chat))
                .zIndex(model.paneMode == .chat ? 1 : 0)
        }
        .onAppear { if model.paneMode == .terminal { terminalWasOpened = true } }
        .onChange(of: model.paneMode) { _, mode in if mode == .terminal { terminalWasOpened = true } }
    }
}

private struct ChatViewIdentity: Hashable {
    let configuration: WebChatConfiguration?
    let generation: UUID?
}

struct MobileChatWorkspace: View {
    @Bindable var model: MobileAppModel
    let target: MobilePromptTarget
    let configureChat: () -> Void
    let openURL: (URL) -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.agentTabVisible) private var rootVisible
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var visible: Bool { rootVisible && model.paneMode == .chat }
    private var controller: ChatTranscriptController? { model.chatController(for: target) }
    private var state: MobileChatDraft { model.chatDraft(for: target) }
    private var draft: Binding<String> {
        Binding(get: { model.agentDraft(paneID: target.paneID, deviceID: target.deviceID) },
                set: { model.setAgentDraft($0, paneID: target.paneID, deviceID: target.deviceID) })
    }

    var body: some View {
        VStack(spacing: 0) {
            if let controller {
                ZStack(alignment: .top) {
                    ChatTranscriptView(renderer: controller.renderer)
                    if case .failed(let error) = controller.state {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(error.localizedDescription).font(.caption)
                            HStack {
                                Button(AppLocalization.string("Refresh")) { controller.refresh() }
                                Button(AppLocalization.string("Chat Service"), action: configureChat)
                            }
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(MobileReferenceTheme.elevated)
                    }
                    if case .loading = controller.state { ProgressView().padding(14) }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right").font(.largeTitle)
                    Text(AppLocalization.string("Connect Chat Service")).mobileFont(.title, weight: .semibold)
                    Text(AppLocalization.string("Bind this development machine to its herdr-web-ui service to read real conversations."))
                        .mobileFont(.body).multilineTextAlignment(.center)
                    Button(AppLocalization.string("Chat Service"), action: configureChat)
                        .buttonStyle(.bordered)
                }
                .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(MobileReferenceTheme.dim)
            }
            if visible {
                MobileChatComposer(text: draft, state: state, agentKind: model.selectedAgent?.agent, modelName: controller?.metadata?.model,
                    reasoningEffort: controller?.metadata?.reasoningEffort, enabled: visible && model.selectedTransportReady,
                    upload: { data, name, contentType in
                        guard let controller, model.currentPromptTarget == target, model.selectedTransportReady else {
                            throw WebChatError.missingCredential
                        }
                        let attachment = try await controller.service.upload(for: controller.target, data: data, contentType: contentType, name: name)
                        guard model.currentPromptTarget == target else { throw WebChatError.staleResponse }
                        return attachment.path
                    }, send: { paths in await model.submitPrompt(target: target, attachmentPaths: paths) })
            }
        }
        .background(MobileReferenceTheme.background)
        .onAppear { updateAppearance(); updateActivity() }
        .onChange(of: visible) { _, _ in updateActivity() }
        .onChange(of: scenePhase) { _, _ in updateActivity() }
        .onChange(of: model.selectedTransportReady) { _, _ in updateActivity() }
        .onChange(of: model.revision) { _, _ in updateActivity() }
        .onChange(of: model.selectedAgent?.status) { _, _ in controller?.refresh() }
        .onChange(of: colorScheme) { _, _ in updateAppearance() }
        .onChange(of: locale.identifier) { _, _ in updateAppearance() }
        .onChange(of: dynamicTypeSize) { _, _ in updateAppearance() }
        .onDisappear { controller?.setActivity(visible: false, foreground: false, connectionValidated: false,
            completionRevision: model.chatCompletionRevision(for: target)) }
    }

    private func updateActivity() {
        guard let controller else { return }
        controller.onOpenURL = openURL
        controller.observeAgentStatus(model.selectedAgent?.status.rawValue ?? "unknown")
        controller.setActivity(visible: visible, foreground: scenePhase == .active,
            connectionValidated: model.selectedTransportReady && model.currentPromptTarget == target,
            completionRevision: model.chatCompletionRevision(for: target))
    }

    private func updateAppearance() {
        let scale: Double
        switch dynamicTypeSize {
        case .accessibility5: scale = 2.6
        case .accessibility4: scale = 2.3
        case .accessibility3: scale = 2.0
        case .accessibility2: scale = 1.7
        case .accessibility1: scale = 1.5
        case .xxxLarge: scale = 1.35
        case .xxLarge: scale = 1.2
        case .xLarge: scale = 1.1
        default: scale = 1
        }
        controller?.setAppearance(theme: colorScheme == .dark ? "dark" : "light",
            language: locale.language.languageCode?.identifier == "zh" ? "zh" : "en", textScale: scale)
    }
}
