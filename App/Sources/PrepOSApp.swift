import SwiftUI

/// Entry point for the PrepOS macOS app (PRD §5.1). This is the thin shell over `PrepOSKit`
/// — the package targets hold the testable logic; the app owns capture surfaces, the
/// cockpit, and the agentic workspace. For now it launches an empty, navigable skeleton
/// (scaffold-plan.md §4) that later pieces fill in.
@main
struct PrepOSApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
        }
    }
}
