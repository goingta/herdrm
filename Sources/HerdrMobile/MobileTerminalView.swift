import GameController
import GhosttyTerminal
import HerdrKit
import HerdrSSH
import SwiftUI
import UIKit

/// The process-wide Ghostty app object for the phone's terminals: every
/// surface shares one controller, mirroring the Mac app's GhosttyRuntime.
/// Both clients resolve the same terminal palette against the App appearance.
@MainActor
enum MobileGhosttyRuntime {
    /// The font/cursor settings land as a configuration override (the
    /// controller's hot-apply path), the theme at construction.
    static let controller: TerminalController = {
        let controller = TerminalController(configSource: .none, theme: makeTheme())
        controller.setTerminalConfiguration(makeConfiguration())
        return controller
    }()

    /// Bundled Nerd Font symbols (MIT, github.com/ryanoasis/nerd-fonts),
    /// registered process-wide at app launch, for the icon glyphs agent
    /// TUIs draw. iOS has no user font cascade for the PUA, so the ranges
    /// are codepoint-mapped like on the Mac.
    private static let symbolFallbackFamily = "Symbols Nerd Font Mono"

    static func registerBundledFonts() {
        guard let url = Bundle.main.url(forResource: "SymbolsNerdFontMono-Regular", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    private static func makeConfiguration() -> TerminalConfiguration {
        TerminalConfiguration { builder in
            builder.withFontSize(12)
            builder.withCursorStyle(.block)
            builder.withCursorStyleBlink(true)
            // Counter the default config's font-thicken: fake bold at
            // terminal sizes reads as smear on a phone screen.
            builder.withFontThicken(false)
            // Menlo is always present on iOS; SF Mono is not resolvable by
            // family name there.
            builder.withFontFamily("Menlo")
            builder.withCustom("font-codepoint-map", "U+E000-U+F8FF=\(symbolFallbackFamily)")
            builder.withCustom("font-codepoint-map", "U+F0000-U+FFFFD=\(symbolFallbackFamily)")
            builder.withCustom("font-codepoint-map", "U+100000-U+10FFFD=\(symbolFallbackFamily)")
        }
    }

    private static func makeTheme() -> TerminalTheme {
        func configuration(dark: Bool) -> TerminalConfiguration {
            TerminalConfiguration { builder in
                builder.withBackground(dark ? "#181613" : "#FAF8F3")
                builder.withForeground(dark ? "#D8D0C3" : "#2A251F")
                builder.withCursorColor(dark ? "#F0A830" : "#8C5000")
                builder.withCursorText(dark ? "#181613" : "#FAF8F3")
                builder.withSelectionBackground(dark ? "#4A3D26" : "#E7D4B2")
                for (index, color) in (dark ? TerminalPalette.darkPalette : TerminalPalette.lightPalette).enumerated() {
                    builder.withPalette(index, color: String(format: "#%02X%02X%02X", color.red, color.green, color.blue))
                }
            }
        }
        return TerminalTheme(light: configuration(dark: false), dark: configuration(dark: true))
    }

}

/// One live attach: a PTY channel running `herdr … attach` on the device,
/// rendered by a host-managed (in-memory) Ghostty surface. The surface's
/// output (keyboard input, DA/OSC replies) and grid resizes flow back
/// through the channel; the channel's bytes feed the surface.
///
/// Mobile terminals are display-first (Heeler's ADR 0013 insight): the live
/// pane renders, typing is opt-in via the keyboard toggle, and the composer
/// (`agent.prompt`) plus key bar (`pane.send_input` keys) go through RPCs so
/// herdr encodes them properly server-side.
@MainActor
final class MobileAttachSession: ObservableObject {
    enum Status: Equatable {
        case connecting
        case running
        case ended(String)
    }

    @Published var status: Status = .connecting
    @Published var stickyModifiers: Set<String> = []
    @Published private(set) var displayRefreshRevision: UInt64 = 0
    @Published private(set) var refreshFailed = false
    private(set) var transport: MobileTransport
    let target: TerminalAttachTarget

    /// The host-managed Ghostty backend the surface in `MobileTerminalHost`
    /// renders. Created up front so the view can attach before the channel
    /// exists — output is buffered by the session until then.
    let terminal: InMemoryTerminalSession
    /// The channel, shared with the session's @Sendable write closure.
    private let channelBox: ChannelBox
    private var channel: SSHPTYChannel?
    private var attachAttempt = UUID()
    private var openTask: Task<Void, Never>?
    private var readTask: Task<Void, Never>?
    /// Last grid the surface reported; reconnects open at this size instead
    /// of waiting for a fresh viewport report (an unchanged grid dispatches
    /// no new resize).
    private var lastGrid: (columns: Int, rows: Int)?
    /// Bytes before the bootstrap marker are shell rc chatter, not pane output.
    private var sawBootstrapMarker = false
    private var bootstrapBuffer = Data()
    private var receivedCurrentOutput = false
    private var generation: UUID?
    private var contentVerified = false
    private var verifying = false
    private var verificationToken = UUID()
    private var presentationEpoch = 0
    private var nextVerification = Date.distantPast
    var readState: AgentReadState?
    var unreadKey: AgentUnreadKey?
    var onReadStateChanged: () -> Void = {}

    private var lightAdapter: LightTerminalANSIAdapter?
    private var lightColorsEnabled: Bool?
    private var appearanceGeneration = UUID()
    private var appearanceRedrawTask: Task<Void, Never>?

    /// Update the renderer and the next PTY bytes in place; never reattach SSH.
    func setLightColorsEnabled(_ enabled: Bool) {
        guard lightColorsEnabled != enabled else { return }
        let wasConfigured = lightColorsEnabled != nil
        lightColorsEnabled = enabled
        lightAdapter = enabled ? LightTerminalANSIAdapter() : nil
        let generation = UUID()
        appearanceGeneration = generation
        // An unchanged grid does not reliably generate SIGWINCH on Linux.
        // Briefly change the PTY grid, then restore the latest actual viewport;
        // this asks the TUI to repaint explicit RGB cells without reattaching.
        if wasConfigured, presentationVisible, let channel, let grid = lastGrid {
            let previous = appearanceRedrawTask
            appearanceRedrawTask = Task { [weak self] in
                await previous?.value
                guard let self, !Task.isCancelled,
                      self.appearanceGeneration == generation,
                      self.channel === channel else { return }
                do {
                    try await channel.resize(columns: grid.columns, rows: max(1, grid.rows - 1), timeout: .seconds(5))
                    // Always restore a changed grid before the next theme's
                    // redraw; a stopped/replaced attach must never be resized.
                    guard self.channel === channel else { return }
                    let current = self.lastGrid ?? grid
                    try await channel.resize(columns: current.columns, rows: current.rows, timeout: .seconds(5))
                } catch {}
            }
        }
    }

    private func render(_ data: Data) {
        if !data.isEmpty { receivedCurrentOutput = true }
        if var adapter = lightAdapter {
            let bytes = [UInt8](data)
            let transformed = adapter.transform(bytes[...])
            lightAdapter = adapter
            if !transformed.isEmpty { terminal.receive(Data(transformed)) }
        } else {
            terminal.receive(data)
        }
    }

    /// The herdr pane behind this attach, for key/prompt RPCs.
    let paneID: String

    init(transport: MobileTransport, target: TerminalAttachTarget, paneID: String, readState: AgentReadState? = nil, unreadKey: AgentUnreadKey? = nil, onReadStateChanged: @escaping () -> Void = {}, transportReady: Bool = true) {
        self.transportReady = transportReady
        self.readState = readState
        self.unreadKey = unreadKey
        self.onReadStateChanged = onReadStateChanged
        self.transport = transport
        self.target = target
        self.paneID = paneID
        let box = ChannelBox()
        channelBox = box
        box.setInputEnabled(transportReady)
        terminal = InMemoryTerminalSession(
            write: { data in box.write(data) },
            resize: { viewport in
                box.resize(columns: Int(viewport.columns), rows: Int(viewport.rows))
            },
            // Only grid changes reach the remote PTY; pixel-only updates
            // would just re-report the same winsize.
            suppressesPixelOnlyResizes: true
        )
        box.owner = self
    }

    var agentPaneID: String? {
        if case .agent(let paneID) = target { return paneID }
        return nil
    }

    /// Recovery keeps the cached frame visible, with input and read proof gated.
    var transportReady = true {
        didSet {
            channelBox.setInputEnabled(transportReady)
            if !transportReady { hidePresentedContent() }
        }
    }

    /// Retain Ghostty scrollback/frame when only the remote connection changes.
    func replaceTransport(_ replacement: MobileTransport) {
        guard transport !== replacement else { return }
        stop()
        transport = replacement
        start()
    }

    /// Attach at the actual viewport; reconnects reuse the last known grid.
    func start() {
        guard transportReady, channel == nil, openTask == nil else { return }
        status = .connecting
        receivedCurrentOutput = false
        contentVerified = false
        if let unreadKey { generation = readState?.beginTerminal(unreadKey) }
        sawBootstrapMarker = false
        bootstrapBuffer.removeAll()
        if let lastGrid {
            open(columns: lastGrid.columns, rows: lastGrid.rows)
        }
    }

    /// The Ghostty IO thread reports the grid here (hopped to main). The
    /// first report opens the channel; later ones resize it.
    private func handleViewportResize(columns: Int, rows: Int) {
        guard presentationVisible else { return }
        lastGrid = (columns, rows)
        if let channel {
            Task { try? await channel.resize(columns: columns, rows: rows, timeout: .seconds(5)) }
            return
        }
        guard transportReady, openTask == nil, case .connecting = status else { return }
        open(columns: columns, rows: rows)
    }

    private func open(columns: Int, rows: Int) {
        let openingTransport = transport
        let attempt = UUID()
        attachAttempt = attempt
        openTask = Task {
            defer { if attachAttempt == attempt { openTask = nil } }
            do {
                let channel = try await openingTransport.openTerminal(
                    command: MobileAttach.command(target: target),
                    columns: max(columns, 20),
                    rows: max(rows, 5)
                )
                guard !Task.isCancelled, attachAttempt == attempt, transport === openingTransport else {
                    try? await channel.close(timeout: .seconds(2)); return
                }
                self.channel = channel
                channelBox.setChannel(channel)
                status = .running
                pump(channel)
                // The grid may have moved while the channel opened.
                if let grid = lastGrid, grid != (columns, rows) {
                    try? await channel.resize(
                        columns: grid.columns, rows: grid.rows, timeout: .seconds(5)
                    )
                }
            } catch {
                guard !Task.isCancelled, attachAttempt == attempt else { return }
                status = .ended(
                    (error as? LocalizedError)?.errorDescription ?? "\(error)"
                )
            }
        }
    }

    private func pump(_ channel: SSHPTYChannel) {
        readTask = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    guard let data = try await channel.read(timeout: .seconds(3600)) else { break }
                    guard !Task.isCancelled, self?.channel === channel else { return }
                    guard !data.isEmpty else { continue }
                    self?.ingest(data)
                }
            } catch {}
            guard let self, !Task.isCancelled, self.channel === channel else { return }
            if case .running = self.status {
                self.status = .ended(AppLocalization.string("Session ended"))
            }
        }
    }

    private func ingest(_ data: Data) {
        guard !sawBootstrapMarker else {
            render(data)
            return
        }
        bootstrapBuffer.append(data)
        guard let range = bootstrapBuffer.firstRange(of: MobileAttach.bootstrapMarker) else {
            // Cap the gate so a herdr that never prints the marker (old
            // binary, exec failure output) still shows its error text.
            if bootstrapBuffer.count > 8192 {
                sawBootstrapMarker = true
                render(bootstrapBuffer)
                bootstrapBuffer.removeAll()
            }
            return
        }
        sawBootstrapMarker = true
        let payload = bootstrapBuffer.suffix(from: range.upperBound)
        bootstrapBuffer.removeAll()
        if !payload.isEmpty { render(Data(payload)) }
    }

    func hidePresentedContent() {
        presentationEpoch += 1
        contentVerified = false
        if let key = unreadKey, let generation { readState?.hideTerminal(key, generation: generation) }
    }

    func verifyPresentedContent(in view: UITerminalView, visible: Bool) {
        guard transportReady, visible, UIApplication.shared.applicationState == .active,
              view.window != nil, case .running = status else { hidePresentedContent(); return }
        guard !contentVerified, !verifying, Date() >= nextVerification, receivedCurrentOutput,
              let key = unreadKey, let generation, let readState,
              let text = terminal.readViewportText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let image = view.snapshotImage()?.cgImage,
              TerminalFrameReadiness.containsRenderedContent(image) else { return }
        verifying = true
        let verification = UUID()
        verificationToken = verification
        nextVerification = Date().addingTimeInterval(1)
        let epoch = presentationEpoch
        Task { @MainActor [weak self, weak view] in
            defer { if self?.verificationToken == verification { self?.verifying = false } }
            guard let self else { return }
            let result = try? await transport.request(method: "pane.read", params: .object([
                "pane_id": .string(key.paneID), "source": .string("visible"), "format": .string("ansi")
            ]))
            guard self.generation == generation, self.presentationEpoch == epoch, view?.window != nil,
                  UIApplication.shared.applicationState == .active, case .running = status,
                  let paneText = result?["read"]?["text"]?.stringValue,
                  AttachContentReadiness.matchesPane(visibleText: text, paneANSIText: paneText) else { return }
            // Visibility may have changed while the RPC was in flight.
            guard self.transportReady, self.presentationVisible else { return }
            contentVerified = true
            readState.presented(key, generation: generation, foreground: true)
            onReadStateChanged()
        }
    }

    var presentationVisible = true {
        didSet { if !presentationVisible { hidePresentedContent() } }
    }

    /// Verify the current pane, then redraw the held surface. The attach and draft stay intact.
    func refreshScreen() async {
        guard transportReady, presentationVisible else { return }
        let currentTransport = transport
        let attempt = attachAttempt
        let epoch = presentationEpoch
        do {
            let response = try await currentTransport.request(method: "pane.read", params: .object([
                "pane_id": .string(paneID), "source": .string("visible"), "format": .string("ansi")
            ]))
            guard transport === currentTransport, attachAttempt == attempt, presentationEpoch == epoch,
                  transportReady, presentationVisible else { return }
            guard response["read"]?["text"]?.stringValue != nil else { throw CancellationError() }
            refreshFailed = false
            displayRefreshRevision &+= 1
        } catch {
            guard transport === currentTransport, attachAttempt == attempt, presentationEpoch == epoch,
                  transportReady, presentationVisible else { return }
            refreshFailed = true
        }
    }

    func toggleModifier(_ modifier: String) {
        guard ["ctrl", "alt", "shift"].contains(modifier) else { return }
        if stickyModifiers.contains(modifier) { stickyModifiers.remove(modifier) } else { stickyModifiers.insert(modifier) }
    }

    /// Named keys preserve all modifier bits in the remote pane keyboard protocol.
    func sendKey(_ key: String) {
        let prefix = ["ctrl", "alt", "shift"].filter { stickyModifiers.contains($0) }
        sendKeys([(prefix + [key]).joined(separator: "+")])
    }

    /// Intercept only a committed ASCII key; composed text and pasted messages remain text.
    func sendModifiedKeyboardText(_ text: String) -> Bool {
        guard !stickyModifiers.isEmpty, text.unicodeScalars.count == 1,
              let scalar = text.unicodeScalars.first, scalar.value < 128 else { return false }
        let key: String
        switch text { case "\r", "\n": key = "enter"; case "\t": key = "tab"; case " ": key = "space"; default: key = text.lowercased() }
        sendKey(key)
        return true
    }

    /// Sends named keys through herdr's RPC — proper terminal encoding without
    /// this client knowing the pane's keyboard protocol state.
    func sendKeys(_ keys: [String]) {
        guard transportReady, presentationVisible else { return }
        let sendingTransport = transport
        Task {
            guard transportReady, presentationVisible, transport === sendingTransport else { return }
            _ = try? await sendingTransport.request(
                method: "pane.send_input",
                params: .object([
                    "pane_id": .string(paneID),
                    "keys": .array(keys.map { .string($0) }),
                ])
            )
        }
    }

    /// Sends a prompt to the agent; herdr delivers and submits it.
    func prompt(_ text: String) async throws {
        guard transportReady, let agentPaneID else { throw CancellationError() }
        let sendingTransport = transport
        _ = try await sendingTransport.request(method: "agent.prompt", params: .object([
            "target": .string(agentPaneID), "text": .string(text)
        ]))
        guard transport === sendingTransport, transportReady else { throw CancellationError() }
    }

    func stop() {
        verificationToken = UUID()
        verifying = false
        attachAttempt = UUID()
        hidePresentedContent()
        if let key = unreadKey, let generation { readState?.endTerminal(key, generation: generation) }
        receivedCurrentOutput = false
        appearanceGeneration = UUID()
        appearanceRedrawTask?.cancel()
        appearanceRedrawTask = nil
        readTask?.cancel()
        readTask = nil
        openTask?.cancel()
        openTask = nil
        if let channel {
            Task { try? await channel.close(timeout: .seconds(2)) }
        }
        channel = nil
        channelBox.setChannel(nil)
    }

    /// The channel as seen from the session's @Sendable closures. Input that
    /// arrives before the channel opens is dropped: keystrokes aimed at a
    /// pane that isn't attached yet are meaningless, and Ghostty's DA/OSC
    /// replies only exist once remote output has been fed.
    private final class ChannelBox: @unchecked Sendable {
        private let lock = NSLock()
        private var channel: SSHPTYChannel?
        private var inputEnabled = true

        func setInputEnabled(_ enabled: Bool) {
            lock.lock(); inputEnabled = enabled; lock.unlock()
        }
        /// Main-actor hop for grid reports from the Ghostty IO thread.
        weak var owner: MobileAttachSession?

        func setChannel(_ channel: SSHPTYChannel?) {
            lock.lock()
            self.channel = channel
            lock.unlock()
        }

        func write(_ data: Data) {
            lock.lock()
            let channel = inputEnabled ? self.channel : nil
            lock.unlock()
            guard let channel else { return }
            Task { try? await channel.write(data, timeout: .seconds(10)) }
        }

        func resize(columns: Int, rows: Int) {
            guard columns > 0, rows > 0 else { return }
            Task { @MainActor [weak owner] in
                owner?.handleViewportResize(columns: columns, rows: rows)
            }
        }
    }
}

struct MobileTerminalScreen: View {
    @StateObject private var session: MobileAttachSession
    @State private var composerText = ""
    private let composerDraft: Binding<String>?
    private let submitPrompt: (() async -> MobilePromptResult)?
    @State private var keyboardShown = false
    @State private var submitting = false
    @State private var promptError = false
    @Environment(\.colorScheme) private var colorScheme
    private let title: String
    private let transport: MobileTransport
    private let transportReady: Bool
    private let refreshRevision: UInt64
    @Environment(\.agentTabVisible) private var agentTabVisible
    private let readState: AgentReadState?
    private let unreadKey: AgentUnreadKey?
    private let onReadStateChanged: () -> Void

    init(transport: MobileTransport, target: TerminalAttachTarget, paneID: String, title: String, composerDraft: Binding<String>? = nil, readState: AgentReadState? = nil, unreadKey: AgentUnreadKey? = nil, onReadStateChanged: @escaping () -> Void = {}, transportReady: Bool = true, submitPrompt: (() async -> MobilePromptResult)? = nil, refreshRevision: UInt64 = 0) {
        self.refreshRevision = refreshRevision
        self.submitPrompt = submitPrompt
        self.transport = transport
        self.transportReady = transportReady
        self.readState = readState
        self.unreadKey = unreadKey
        self.onReadStateChanged = onReadStateChanged
        _session = StateObject(
            wrappedValue: MobileAttachSession(transport: transport, target: target, paneID: paneID, readState: readState, unreadKey: unreadKey, onReadStateChanged: onReadStateChanged, transportReady: transportReady)
        )
        self.title = title
        self.composerDraft = composerDraft
    }

    var body: some View {
        ZStack {
            terminalBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                MobileTerminalHost(session: session, keyboardShown: $keyboardShown, presentationVisible: agentTabVisible)
                if agentTabVisible {
                    if session.refreshFailed { Text(AppLocalization.string("Could Not Refresh Terminal")).font(.caption).foregroundStyle(MobileReferenceTheme.dim).padding(6) }
                    controls.disabled(!transportReady)
                }
            }
            if transportReady, case .ended(let reason) = session.status {
                endedOverlay(reason)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .toolbarBackground(terminalBackground, for: .navigationBar)
        .onAppear {
            session.transportReady = transportReady
            session.readState = readState
            session.unreadKey = unreadKey
            session.onReadStateChanged = onReadStateChanged
        }
        .onChange(of: ObjectIdentifier(transport)) { _, _ in
            if transportReady, agentTabVisible { session.replaceTransport(transport) }
        }
        .onChange(of: transportReady) { _, value in
            session.transportReady = value
            guard value, agentTabVisible else { return }
            session.replaceTransport(transport)
            if case .ended = session.status { session.stop() }
            session.start()
        }
        .onChange(of: refreshRevision) { _, _ in Task { await session.refreshScreen() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in session.hidePresentedContent() }
        .onChange(of: agentTabVisible) { _, value in
            session.presentationVisible = value
            if value, transportReady { session.replaceTransport(transport); session.start() }
        }
    }

    private var terminalBackground: SwiftUI.Color {
        Theme.terminalBackground
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if promptError { Text(AppLocalization.string("Message not confirmed. Draft retained; check the Agent before retrying."))
                .font(.caption).foregroundStyle(Theme.warning) }
            if session.agentPaneID != nil { composer }
            keyBar
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Theme.statusBarBackground)
    }

    private var keyBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 5) {
                Button { keyboardShown.toggle() } label: {
                    Image(systemName: keyboardShown ? "keyboard.chevron.compact.down" : "keyboard")
                        .frame(width: 44, height: 44)
                        .background(MobileReferenceTheme.input, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MobileReferenceTheme.border))
                }
                .accessibilityIdentifier("agent.keyboard")
                .accessibilityLabel(keyboardShown ? AppLocalization.string("Hide Keyboard") : AppLocalization.string("Show Keyboard"))
                KeyChip("Esc", accessibilityLabel: AppLocalization.string("Escape")) { session.sendKey("esc") }
                KeyChip("Tab", accessibilityLabel: AppLocalization.string("Tab")) { session.sendKey("tab") }
                ForEach(["ctrl", "alt", "shift"], id: \.self) { key in
                    KeyChip(key.capitalized, accessibilityLabel: key.capitalized, pressed: session.stickyModifiers.contains(key)) { session.toggleModifier(key) }
                        .accessibilityIdentifier("terminal.modifier.\(key)")
                        .accessibilityAddTraits(session.stickyModifiers.contains(key) ? [.isSelected] : [])
                }
                KeyChip("Enter", accessibilityLabel: AppLocalization.string("Enter")) { session.sendKey("enter") }
                KeyChip("↑", accessibilityLabel: AppLocalization.string("Move Up")) { session.sendKey("up") }
                KeyChip("↓", accessibilityLabel: AppLocalization.string("Move Down")) { session.sendKey("down") }
                KeyChip("←", accessibilityLabel: AppLocalization.string("Move Left")) { session.sendKey("left") }
                KeyChip("→", accessibilityLabel: AppLocalization.string("Move Right")) { session.sendKey("right") }
            }
        }
        .foregroundStyle(MobileReferenceTheme.dim)
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("terminal.keys")
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(
                AppLocalization.string("Message the agent…"),
                text: draft,
                axis: .vertical
            )
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.itemWash, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(MobileReferenceTheme.border))
            .frame(minHeight: 44)
            .foregroundStyle(Theme.text)
            .tint(Theme.accent)
            .accessibilityIdentifier("agent.composer")
            .onSubmit(sendPrompt)

            Button(action: sendPrompt) {
                Image(systemName: "return")
                    .font(.system(size: 23, weight: .medium))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(MobileReferenceTheme.background)
                    .background(MobileReferenceTheme.primary, in: Circle())
            }
            .disabled(submitting || draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(AppLocalization.string("Send Prompt"))
            .accessibilityIdentifier("agent.send")
        }
    }

    private func sendPrompt() {
        let original = draft.wrappedValue
        let text = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !submitting, transportReady else { return }
        submitting = true
        promptError = false
        Task {
            defer { submitting = false }
            do {
                if let submitPrompt {
                    let result = await submitPrompt()
                    promptError = result != .acknowledged
                } else {
                    try await session.prompt(text)
                    if draft.wrappedValue == original { draft.wrappedValue = "" }
                }
            } catch { promptError = true }
        }
    }

    private var draft: Binding<String> { composerDraft ?? $composerText }

    private func endedOverlay(_ reason: String) -> some View {
        VStack(spacing: 12) {
            Text(reason)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            Button(AppLocalization.string("Reconnect")) {
                session.stop()
                session.start()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(Theme.contentBackground.opacity(0.94), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Display-first: a tap on the terminal is a click for the TUI, never a
/// keyboard pop — the toolbar button owns the software keyboard. With a
/// hardware keyboard attached (iPad), the tap still claims first responder
/// so keystrokes land; iOS then shows only the accessory bar.
private final class MobileGhosttyTerminalView: UITerminalView {
    var modifiedKeyboardText: ((String) -> Bool)?
    override func insertText(_ text: String) {
        if modifiedKeyboardText?(text) == true { return }
        super.insertText(text)
    }
    override func toggleSoftwareKeyboard() {
        if GCKeyboard.coalesced != nil {
            _ = becomeFirstResponder()
        }
    }
}

/// UIKit host for Ghostty's UITerminalView on the session's in-memory
/// backend, wired to the attach session.
private struct MobileTerminalHost: UIViewRepresentable {
    let session: MobileAttachSession
    @Binding var keyboardShown: Bool
    var presentationVisible: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> MobileGhosttyTerminalView {
        let view = MobileGhosttyTerminalView(frame: .zero)
        view.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        session.setLightColorsEnabled(colorScheme == .light)
        MobileGhosttyRuntime.controller.setColorScheme(colorScheme == .dark ? .dark : .light)
        view.modifiedKeyboardText = { [weak session] in session?.sendModifiedKeyboardText($0) ?? false }
        view.controller = MobileGhosttyRuntime.controller
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(session.terminal))
        context.coordinator.observeKeyboard(for: view)
        context.coordinator.session = session
        session.presentationVisible = presentationVisible
        context.coordinator.startPresentationChecks()
        // Publishing ObservableObject state during makeUIView triggers a
        // SwiftUI re-entrant update. Start in a cancellable later actor turn.
        context.coordinator.scheduleStart(session)
        return view
    }

    func updateUIView(_ uiView: MobileGhosttyTerminalView, context: Context) {
        uiView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        MobileGhosttyRuntime.controller.setColorScheme(colorScheme == .dark ? .dark : .light)
        session.setLightColorsEnabled(colorScheme == .light)
        session.presentationVisible = presentationVisible
        if context.coordinator.refreshRevision != session.displayRefreshRevision {
            context.coordinator.refreshRevision = session.displayRefreshRevision
            uiView.setSurfaceVisible(false)
        }
        uiView.setSurfaceVisible(presentationVisible)
        if keyboardShown && presentationVisible && UIApplication.shared.applicationState == .active {
            uiView.acquireProgrammaticFocus()
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ uiView: MobileGhosttyTerminalView, coordinator: Coordinator) {
        coordinator.stopPresentationChecks()
        coordinator.cancelStart()
        coordinator.session?.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator(keyboardShown: $keyboardShown) }

    /// Keeps the keyboard binding truthful when the keyboard comes or goes
    /// outside the toolbar button (interactive dismiss, hardware attach).
    final class Coordinator: NSObject {
        var keyboardShown: Binding<Bool>
        var refreshRevision: UInt64 = 0
        weak var view: MobileGhosttyTerminalView?
        weak var session: MobileAttachSession?
        nonisolated(unsafe) private var presentationTimer: Timer?
        private var startTask: Task<Void, Never>?

        func scheduleStart(_ session: MobileAttachSession) {
            startTask?.cancel()
            startTask = Task { @MainActor [weak session] in
                await Task.yield()
                guard !Task.isCancelled else { return }
                session?.start()
            }
        }
        func cancelStart() { startTask?.cancel(); startTask = nil }

        func startPresentationChecks() {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let view = self.view, let session = self.session else { return }
                    session.verifyPresentedContent(in: view, visible: session.presentationVisible)
                }
            }
            presentationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        func stopPresentationChecks() { presentationTimer?.invalidate(); presentationTimer = nil }


        init(keyboardShown: Binding<Bool>) {
            self.keyboardShown = keyboardShown
        }

        func observeKeyboard(for view: MobileGhosttyTerminalView) {
            self.view = view
            NotificationCenter.default.addObserver(
                self, selector: #selector(keyboardDidShow),
                name: UIResponder.keyboardDidShowNotification, object: nil
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(keyboardDidHide),
                name: UIResponder.keyboardDidHideNotification, object: nil
            )
        }

        deinit {
            presentationTimer?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func keyboardDidShow(_: Notification) {
            guard view?.isFirstResponder == true, !keyboardShown.wrappedValue else { return }
            keyboardShown.wrappedValue = true
        }

        @objc private func keyboardDidHide(_: Notification) {
            guard keyboardShown.wrappedValue else { return }
            keyboardShown.wrappedValue = false
        }
    }
}

private struct KeyChip: View {
    let label: String
    let accessibilityLabel: String
    let action: () -> Void
    let pressed: Bool

    init(_ label: String, accessibilityLabel: String, pressed: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.accessibilityLabel = accessibilityLabel
        self.pressed = pressed
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout.monospaced().weight(.medium))
                .foregroundStyle(pressed ? MobileReferenceTheme.accent : MobileReferenceTheme.dim)
                .frame(minWidth: 50)
                .frame(minHeight: 44)
                .background(MobileReferenceTheme.input, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(pressed ? MobileReferenceTheme.accent : MobileReferenceTheme.border))
        }
        .accessibilityLabel(accessibilityLabel)
    }
}
