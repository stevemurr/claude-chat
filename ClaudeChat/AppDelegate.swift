import AppKit
import SwiftUI
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    private var eventMonitor: Any?
    private var localEventMonitor: Any?
    private var hotkeyObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupWindow()
        registerHotkey()

        // Listen for hotkey changes
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reregisterHotkey()
        }
    }

    private func setupWindow() {
        // Get the existing window created by SwiftUI
        guard let window = NSApplication.shared.windows.first else { return }
        self.window = window

        // Configure window behavior
        window.level = .floating
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor.windowBackgroundColor

        // Center and set size
        window.setContentSize(NSSize(width: 600, height: 500))
        window.center()

        // Handle window close to hide instead of terminate
        window.delegate = self
    }

    private func registerHotkey() {
        // Global monitor (when app is not focused)
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // Local monitor (when app is focused)
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil // Consume the event
            }
            return event
        }
    }

    private func reregisterHotkey() {
        // Remove old monitors
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        // Register new ones
        registerHotkey()
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hotkey = SettingsManager.shared.hotkey

        // Check if this matches the configured hotkey
        if event.keyCode == hotkey.keyCode && flags.rawValue == hotkey.modifiers {
            toggleWindow()
            return true
        }

        // Escape to hide when visible
        if event.keyCode == 53 && window?.isVisible == true { // 53 = Escape
            hideWindow()
            return true
        }

        // Cmd+N for new chat
        if event.keyCode == 45 && flags == .command && window?.isVisible == true { // 45 = N
            NotificationCenter.default.post(name: .newChat, object: nil)
            return true
        }

        return false
    }

    func toggleWindow() {
        guard let window = window else { return }

        if window.isVisible && window.isKeyWindow {
            hideWindow()
        } else {
            showWindow()
        }
    }

    func showWindow() {
        guard let window = window else { return }

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Notify SwiftUI to focus the text field
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .focusInput, object: nil)
        }
    }

    func hideWindow() {
        window?.orderOut(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = hotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

extension Notification.Name {
    static let focusInput = Notification.Name("focusInput")
    static let newChat = Notification.Name("newChat")
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of close
        hideWindow()
        return false
    }

    func windowDidResignKey(_ notification: Notification) {
        // Optional: Hide when clicking outside
        // hideWindow()
    }
}
