import SwiftUI

enum MobileAppTab: CaseIterable {
    case agent, preview, settings

    var title: String {
        switch self {
        case .agent: AppLocalization.string("Agent")
        case .preview: AppLocalization.string("Project Preview")
        case .settings: AppLocalization.string("Settings")
        }
    }

    var symbol: String {
        switch self {
        case .agent: "terminal"
        case .preview: "globe"
        case .settings: "gearshape"
        }
    }
}

/// The three roots remain mounted: changing tabs must not destroy the Agent's
/// composer/PTY surface or rebuild a website and lose its navigation history.
struct MobileWorkspaceView: View {
    @Bindable var model: MobileAppModel
    @State private var browser = ProjectPreviewBrowser()
    @State private var selectedTab: MobileAppTab = .agent

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                MobileRootView(model: model)
                    .environment(\.agentTabVisible, selectedTab == .agent)
                    .tabVisibility(selectedTab == .agent)
                ProjectPreviewView(browser: browser, returnToAgent: { selectedTab = .agent })
                    .tabVisibility(selectedTab == .preview)
                MobileSettingsView()
                    .tabVisibility(selectedTab == .settings)
            }
            Divider().overlay(Theme.hairline)
            HStack(spacing: 0) {
                ForEach(MobileAppTab.allCases, id: \.self) { tab in
                    Button {
                        dismissKeyboard()
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.symbol).font(.title3)
                            Text(tab.title).font(.caption).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(selectedTab == tab ? Theme.accent : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: VisualMetrics.minimumTouchTarget)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tab.\(tab)")
                    .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
                }
            }
            .background(Theme.statusBarBackground)
        }
        .background(Theme.contentBackground)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private extension View {
    func tabVisibility(_ visible: Bool) -> some View {
        opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}
