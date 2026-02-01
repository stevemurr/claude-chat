import SwiftUI

@main
struct ClaudeChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 600, height: 500)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
