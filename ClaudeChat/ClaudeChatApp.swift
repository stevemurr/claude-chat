import SwiftUI

@main
struct ClaudeChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 700, height: 550)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) { }
        }
    }
}
