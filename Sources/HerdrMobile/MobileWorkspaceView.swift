import SwiftUI
import Observation

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

@MainActor
@Observable
final class MobileWorkspaceNavigation {
    var selectedTab: MobileAppTab = .agent
    let browser = ProjectPreviewBrowser()
}

/// The three roots remain mounted: changing tabs must not destroy the Agent's
/// composer/PTY surface or rebuild a website and lose its navigation history.
@MainActor
struct MobileWorkspaceView: View {
    @Bindable var model: MobileAppModel
    @State private var navigation: MobileWorkspaceNavigation

    init(model: MobileAppModel, navigation: MobileWorkspaceNavigation? = nil) {
        self.model = model
        _navigation = State(initialValue: navigation ?? MobileWorkspaceNavigation())
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                MobileRootView(model: model)
                    .environment(\.agentTabVisible, navigation.selectedTab == .agent)
                    .tabVisibility(navigation.selectedTab == .agent)
                ProjectPreviewView(browser: navigation.browser, returnToAgent: { navigation.selectedTab = .agent })
                    .tabVisibility(navigation.selectedTab == .preview)
                MobileSettingsView(showsDoneButton: false)
                    .tabVisibility(navigation.selectedTab == .settings)
            }
            Divider().overlay(Theme.hairline)
            HStack(spacing: 0) {
                ForEach(MobileAppTab.allCases, id: \.self) { tab in
                    Button {
                        dismissKeyboard()
                        navigation.selectedTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.symbol).font(.title3)
                            Text(tab.title).font(.caption).multilineTextAlignment(.center)
                        }
                        .foregroundStyle(navigation.selectedTab == tab ? Theme.accent : Theme.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: VisualMetrics.minimumTouchTarget)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tab.\(tab)")
                    .accessibilityAddTraits(navigation.selectedTab == tab ? [.isSelected] : [])
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
