import AppKit
import SwiftUI
import Carbon.HIToolbox

// Global callback for Carbon hotkey
private var globalHotkeyHandler: (() -> Void)?

private func carbonHotkeyCallback(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    globalHotkeyHandler?()
    return noErr
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var localEventMonitor: Any?
    private var hotkeyObserver: Any?
    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

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

        let newNoteItem = NSMenuItem(title: "New Note", action: #selector(newNoteAction), keyEquivalent: "n")
        newNoteItem.keyEquivalentModifierMask = [.command, .shift]
        newNoteItem.target = self
        menu.addItem(newNoteItem)

        let searchItem = NSMenuItem(title: "Search...", action: #selector(searchAction), keyEquivalent: "k")
        searchItem.keyEquivalentModifierMask = .command
        searchItem.target = self
        menu.addItem(searchItem)

        let toggleModeItem = NSMenuItem(title: "Toggle Mode", action: #selector(toggleModeAction), keyEquivalent: "")
        toggleModeItem.target = self
        menu.addItem(toggleModeItem)

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

    @objc private func newNoteAction() {
        showWindow()
        NotificationCenter.default.post(name: .newNote, object: nil)
    }

    @objc private func searchAction() {
        showWindow()
        NotificationCenter.default.post(name: .openCommandPalette, object: nil)
    }

    @objc private func toggleModeAction() {
        showWindow()
        NotificationCenter.default.post(name: .toggleMode, object: nil)
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
        let hotkey = SettingsManager.shared.hotkey

        // Set up the global callback
        globalHotkeyHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.toggleWindow()
            }
        }

        // Register Carbon hotkey for global detection
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyCallback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if status != noErr {
            print("Failed to install event handler: \(status)")
        }

        // Convert NSEvent modifier flags to Carbon modifiers
        var carbonModifiers: UInt32 = 0
        let modifiers = UInt(hotkey.modifiers)

        if modifiers & NSEvent.ModifierFlags.command.rawValue != 0 {
            carbonModifiers |= UInt32(cmdKey)
        }
        if modifiers & NSEvent.ModifierFlags.option.rawValue != 0 {
            carbonModifiers |= UInt32(optionKey)
        }
        if modifiers & NSEvent.ModifierFlags.control.rawValue != 0 {
            carbonModifiers |= UInt32(controlKey)
        }
        if modifiers & NSEvent.ModifierFlags.shift.rawValue != 0 {
            carbonModifiers |= UInt32(shiftKey)
        }

        var hotkeyID = EventHotKeyID(signature: OSType(0x434C4454), id: 1) // 'CLDT'

        let registerStatus = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        if registerStatus != noErr {
            print("Failed to register hotkey: \(registerStatus)")
        }

        // Local monitor for escape and other keys when app is focused
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleLocalKeyEvent(event) == true {
                return nil // Consume the event
            }
            return event
        }
    }

    private func reregisterHotkey() {
        // Unregister old hotkey
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        // Register new ones
        registerHotkey()
    }

    @discardableResult
    private func handleLocalKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hotkey = SettingsManager.shared.hotkey

        // Check if this matches the configured hotkey (for when app is focused)
        if event.keyCode == hotkey.keyCode && flags.rawValue == hotkey.modifiers {
            toggleWindow()
            return true
        }

        // Escape to hide when visible (but not when command palette is open)
        if event.keyCode == 53 && window?.isVisible == true { // 53 = Escape
            if CommandPaletteState.isVisible {
                return false // Let the palette handle Escape
            }
            hideWindow()
            return true
        }

        // Shift+Tab to cycle modes
        if event.keyCode == 48 && flags == .shift && window?.isVisible == true { // 48 = Tab
            NotificationCenter.default.post(name: .toggleMode, object: nil)
            return true
        }

        // Cmd+Shift+N for new note
        if event.keyCode == 45 && flags == [.command, .shift] && window?.isVisible == true {
            NotificationCenter.default.post(name: .newNote, object: nil)
            return true
        }

        // Cmd+N for new chat (context-aware via ContentView)
        if event.keyCode == 45 && flags == .command && window?.isVisible == true { // 45 = N
            NotificationCenter.default.post(name: .newChat, object: nil)
            return true
        }

        // Cmd+K for command palette
        if event.keyCode == 40 && flags == .command && window?.isVisible == true { // 40 = K
            NotificationCenter.default.post(name: .openCommandPalette, object: nil)
            return true
        }

        // Cmd+, for settings
        if event.keyCode == 43 && flags == .command && window?.isVisible == true { // 43 = comma
            NotificationCenter.default.post(name: .openSettings, object: nil)
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
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
        }
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = hotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        globalHotkeyHandler = nil
    }
}

extension Notification.Name {
    static let focusInput = Notification.Name("focusInput")
    static let newChat = Notification.Name("newChat")
    static let newNote = Notification.Name("newNote")
    static let toggleMode = Notification.Name("toggleMode")
    static let openSettings = Notification.Name("openSettings")
    static let openCommandPalette = Notification.Name("openCommandPalette")
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
