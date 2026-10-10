import SwiftUI
import WebKit

struct ProjectPreviewView: View {
    @Bindable var browser: ProjectPreviewBrowser
    let returnToAgent: () -> Void
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        TextField(AppLocalization.string("https://example.com"), text: $address, axis: .vertical)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($addressFocused)
                            .lineLimit(1...3)
                            .padding(10)
                            .background(Theme.contentBackground, in: RoundedRectangle(cornerRadius: VisualMetrics.controlRadius))
                            .accessibilityLabel(AppLocalization.string("Preview URL"))
                            .accessibilityIdentifier("preview.address")
                            .onSubmit(open)
                        Button(AppLocalization.string("Open"), action: open)
                            .frame(minHeight: VisualMetrics.minimumTouchTarget)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("preview.open")
                    }
                    Text(AppLocalization.string("Direct access · HTTP / HTTPS"))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    if let target = browser.targetURL {
                        Text(target.absoluteString)
                            .font(.caption).foregroundStyle(Theme.text)
                            .lineLimit(3).textSelection(.enabled)
                            .accessibilityLabel(AppLocalization.string("Current Preview Target"))
                    }
                    navigationControls
                }
                .padding(12)
                .background(Theme.statusBarBackground)
                Divider().overlay(Theme.hairline)
                if browser.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(4)
                        .accessibilityLabel(AppLocalization.string("Loading Preview…"))
                }
                if let error = browser.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(.callout).foregroundStyle(Theme.danger)
                        Button(AppLocalization.string("Retry")) { addressFocused = false; browser.reload() }
                            .frame(minHeight: VisualMetrics.minimumTouchTarget)
                            .buttonStyle(.bordered)
                            .disabled(browser.targetURL == nil)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(Theme.statusBarBackground)
                    .accessibilityIdentifier("preview.error")
                }
                ZStack {
                    PreviewWebSurface(browser: browser)
                    if browser.targetURL == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "globe").font(.title).foregroundStyle(Theme.textSecondary)
                            Text(AppLocalization.string("Enter a project URL to preview it here."))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.contentBackground)
                    }
                }
            }
            .navigationTitle(AppLocalization.string("Project Preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { addressFocused = false; returnToAgent() }) {
                        Label(AppLocalization.string("Back to Agent"), systemImage: "terminal")
                    }
                }
            }
        }
    }

    private var navigationControls: some View {
        HStack {
            navigationButton("chevron.left", "Back", disabled: !browser.canGoBack, action: browser.goBack)
            navigationButton("chevron.right", "Forward", disabled: !browser.canGoForward, action: browser.goForward)
            navigationButton("arrow.clockwise", "Refresh", disabled: browser.targetURL == nil, action: browser.reload)
            Spacer()
            navigationButton("keyboard.chevron.compact.down", "Hide Keyboard", disabled: false) { addressFocused = false }
        }
    }

    private func navigationButton(_ symbol: String, _ key: String.LocalizationValue,
                                  disabled: Bool, action: @escaping () -> Void) -> some View {
        Button { addressFocused = false; action() } label: {
            Image(systemName: symbol)
                .frame(minWidth: VisualMetrics.minimumTouchTarget, minHeight: VisualMetrics.minimumTouchTarget)
        }
        .buttonStyle(.plain).disabled(disabled)
        .accessibilityLabel(AppLocalization.string(key))
    }

    private func open() {
        if browser.open(address) { addressFocused = false }
    }
}

private struct PreviewWebSurface: UIViewRepresentable {
    let browser: ProjectPreviewBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
