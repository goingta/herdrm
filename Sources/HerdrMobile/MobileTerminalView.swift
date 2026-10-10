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

    private static func makeTheme() -> TerminalTheme { TerminalPalette.makeTheme() }

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
    let transport: MobileTransport
    let target: TerminalAttachTarget

    /// The host-managed Ghostty backend the surface in `MobileTerminalHost`
    /// renders. Created up front so the view can attach before the channel
    /// exists — output is buffered by the session until then.
    let terminal: InMemoryTerminalSession
    /// The channel, shared with the session's @Sendable write closure.
    private let channelBox: ChannelBox
    private var channel: SSHPTYChannel?
    private var openTask: Task<Void, Never>?
    private var readTask: Task<Void, Never>?
    /// Last grid the surface reported; reconnects open at this size instead
    /// of waiting for a fresh viewport report (an unchanged grid dispatches
    /// no new resize).
    private var lastGrid: (columns: Int, rows: Int)?
    /// Bytes before the bootstrap marker are shell rc chatter, not pane output.
    private var sawBootstrapMarker = false
    private var bootstrapBuffer = Data()
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
        if wasConfigured, let channel, let grid = lastGrid {
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

    init(transport: MobileTransport, target: TerminalAttachTarget, paneID: String) {
        self.transport = transport
        self.target = target
        self.paneID = paneID
        let box = ChannelBox()
        channelBox = box
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

    /// Marks the session ready to attach. The channel opens on the surface's
    /// first viewport report (the exact grid, no SIGWINCH redraw); a
    /// reconnect reuses the last grid and opens immediately.
    func start() {
        guard channel == nil, openTask == nil else { return }
        status = .connecting
        sawBootstrapMarker = false
        bootstrapBuffer.removeAll()
        if let lastGrid {
            open(columns: lastGrid.columns, rows: lastGrid.rows)
        }
    }

    /// The Ghostty IO thread reports the grid here (hopped to main). The
    /// first report opens the channel; later ones resize it.
    private func handleViewportResize(columns: Int, rows: Int) {
        lastGrid = (columns, rows)
        if let channel {
            Task { try? await channel.resize(columns: columns, rows: rows, timeout: .seconds(5)) }
            return
        }
        guard openTask == nil, case .connecting = status else { return }
        open(columns: columns, rows: rows)
    }

    private func open(columns: Int, rows: Int) {
        openTask = Task {
            defer { openTask = nil }
            do {
                let channel = try await transport.openTerminal(
                    command: MobileAttach.command(target: target),
                    columns: max(columns, 20),
                    rows: max(rows, 5)
                )
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
                    guard !data.isEmpty else { continue }
                    self?.ingest(data)
                }
            } catch {}
            guard let self, !Task.isCancelled else { return }
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

    /// Sends named keys through herdr's RPC — proper terminal encoding without
    /// this client knowing the pane's keyboard protocol state.
    func sendKeys(_ keys: [String]) {
        Task {
            _ = try? await transport.request(
                method: "pane.send_input",
                params: .object([
                    "pane_id": .string(paneID),
                    "keys": .array(keys.map { .string($0) }),
                ])
            )
        }
    }

    /// Sends a prompt to the agent; herdr delivers and submits it.
    func prompt(_ text: String) {
        guard let agentPaneID else { return }
        Task {
            _ = try? await transport.request(
                method: "agent.prompt",
                params: .object([
                    "target": .string(agentPaneID),
                    "text": .string(text),
                ])
            )
        }
    }

    func stop() {
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
        /// Main-actor hop for grid reports from the Ghostty IO thread.
        weak var owner: MobileAttachSession?

        func setChannel(_ channel: SSHPTYChannel?) {
            lock.lock()
            self.channel = channel
            lock.unlock()
        }

        func write(_ data: Data) {
            lock.lock()
            let channel = self.channel
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
    @State private var keyboardShown = false
    @Environment(\.colorScheme) private var colorScheme
    private let title: String

    init(transport: MobileTransport, target: TerminalAttachTarget, paneID: String, title: String) {
        _session = StateObject(
            wrappedValue: MobileAttachSession(transport: transport, target: target, paneID: paneID)
        )
        self.title = title
    }

    var body: some View {
        ZStack {
            terminalBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                MobileTerminalHost(session: session, keyboardShown: $keyboardShown)
                controls
            }
            if case .ended(let reason) = session.status {
                endedOverlay(reason)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .toolbarBackground(terminalBackground, for: .navigationBar)
        .onDisappear { session.stop() }
    }

    private var terminalBackground: SwiftUI.Color {
        Theme.terminalBackground
    }

    private var controls: some View {
        VStack(spacing: 8) {
            keyBar
            if session.agentPaneID != nil {
                composer
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Theme.statusBarBackground)
    }

    private var keyBar: some View {
        HStack(spacing: 8) {
            KeyChip("esc", accessibilityLabel: AppLocalization.string("Escape")) { session.sendKeys(["esc"]) }
            KeyChip("tab", accessibilityLabel: AppLocalization.string("Tab")) { session.sendKeys(["tab"]) }
            KeyChip("↑", accessibilityLabel: AppLocalization.string("Move Up")) { session.sendKeys(["up"]) }
            KeyChip("↓", accessibilityLabel: AppLocalization.string("Move Down")) { session.sendKeys(["down"]) }
            KeyChip("⏎", accessibilityLabel: AppLocalization.string("Enter")) { session.sendKeys(["enter"]) }
            KeyChip("^C", accessibilityLabel: AppLocalization.string("Interrupt (Control-C)")) { session.sendKeys(["ctrl+c"]) }
            Spacer()
            Button {
                keyboardShown.toggle()
            } label: {
                Image(systemName: keyboardShown ? "keyboard.chevron.compact.down" : "keyboard")
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 34, height: 30)
                    .background(Theme.itemWash, in: RoundedRectangle(cornerRadius: 7))
            }
            .accessibilityLabel(keyboardShown ? AppLocalization.string("Hide Keyboard") : AppLocalization.string("Show Keyboard"))
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField(
                AppLocalization.string("Message the agent…"),
                text: $composerText,
                axis: .vertical
            )
            .lineLimit(1...4)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.itemWash, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(Theme.text)
            .tint(Theme.accent)
            .onSubmit(sendPrompt)

            Button(action: sendPrompt) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(
                        composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Theme.textGhost : Theme.accent
                    )
            }
            .disabled(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(AppLocalization.string("Send Prompt"))
        }
    }

    private func sendPrompt() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        session.prompt(text)
        composerText = ""
    }

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
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> MobileGhosttyTerminalView {
        let view = MobileGhosttyTerminalView(frame: .zero)
        view.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        session.setLightColorsEnabled(colorScheme == .light)
        MobileGhosttyRuntime.controller.setColorScheme(colorScheme == .dark ? .dark : .light)
        view.controller = MobileGhosttyRuntime.controller
        view.configuration = TerminalSurfaceOptions(backend: .inMemory(session.terminal))
        context.coordinator.observeKeyboard(for: view)
        session.start()
        return view
    }

    func updateUIView(_ uiView: MobileGhosttyTerminalView, context _: Context) {
        uiView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        MobileGhosttyRuntime.controller.setColorScheme(colorScheme == .dark ? .dark : .light)
        session.setLightColorsEnabled(colorScheme == .light)
        if keyboardShown {
            uiView.acquireProgrammaticFocus()
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(keyboardShown: $keyboardShown) }

    /// Keeps the keyboard binding truthful when the keyboard comes or goes
    /// outside the toolbar button (interactive dismiss, hardware attach).
    final class Coordinator: NSObject {
        var keyboardShown: Binding<Bool>
        weak var view: MobileGhosttyTerminalView?

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

    init(_ label: String, accessibilityLabel: String, action: @escaping () -> Void) {
        self.label = label
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 34)
                .frame(height: 30)
                .padding(.horizontal, 4)
                .background(Theme.itemWash, in: RoundedRectangle(cornerRadius: 7))
        }
        .accessibilityLabel(accessibilityLabel)
    }
}
