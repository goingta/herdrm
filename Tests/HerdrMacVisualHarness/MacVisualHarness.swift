import SwiftUI

/// Independent test host; no production AppDelegate or real service startup.
@main
struct MacVisualHarness: App {
    var body: some Scene {
        WindowGroup { MacEvidenceScene() }
            .windowResizability(.contentSize)
    }
}
