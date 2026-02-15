import SwiftUI

@main
struct ClaudeChatApp: App {
    init() {
        // Initialize SettingsManager early to trigger URL migration
        _ = SettingsManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
