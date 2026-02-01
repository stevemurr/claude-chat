import AppKit
import SwiftUI
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var eventMonitor: Any?
    private var localEventMonitor: Any?
    private var hotkeyObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupWindow()
        registerHotkey()

        // Listen for hotkey changes
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reregisterHotkey()
            self?.updateMenuBarHotkeyDisplay()
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "bubble.left.fill", accessibilityDescription: "ClaudeChat")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()

        let showItem = NSMenuItem(title: "Show Window", action: #selector(showWindowAction), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let newChatItem = NSMenuItem(title: "New Chat", action: #selector(newChatAction), keyEquivalent: "n")
        newChatItem.keyEquivalentModifierMask = .command
        newChatItem.target = self
        menu.addItem(newChatItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsAction), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let hotkeyItem = NSMenuItem(title: "Hotkey: \(SettingsManager.shared.hotkey.displayString)", action: nil, keyEquivalent: "")
        hotkeyItem.isEnabled = false
        hotkeyItem.tag = 100 // Tag to find it later for updates
        menu.addItem(hotkeyItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit ClaudeChat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    private func updateMenuBarHotkeyDisplay() {
        if let menu = statusItem?.menu,
           let hotkeyItem = menu.item(withTag: 100) {
            hotkeyItem.title = "Hotkey: \(SettingsManager.shared.hotkey.displayString)"
        }
    }

    @objc private func showWindowAction() {
        showWindow()
    }

    @objc private func newChatAction() {
        showWindow()
        NotificationCenter.default.post(name: .newChat, object: nil)
    }

    @objc private func openSettingsAction() {
        showWindow()
        NotificationCenter.default.post(name: .openSettings, object: nil)
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
    static let openSettings = Notification.Name("openSettings")
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
