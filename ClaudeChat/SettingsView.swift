import SwiftUI
import Carbon.HIToolbox

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt

    static let `default` = HotkeyConfig(keyCode: 49, modifiers: NSEvent.ModifierFlags.command.union(.shift).rawValue) // Cmd+Shift+Space

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    var displayString: String {
        var parts: [String] = []

        if modifierFlags.contains(.control) { parts.append("⌃") }
        if modifierFlags.contains(.option) { parts.append("⌥") }
        if modifierFlags.contains(.shift) { parts.append("⇧") }
        if modifierFlags.contains(.command) { parts.append("⌘") }

        parts.append(keyCodeToString(keyCode))

        return parts.joined()
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        let keyMap: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
            50: "`", 51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7",
            99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13",
            107: "F14", 109: "F10", 111: "F12", 113: "F15", 118: "F4",
            119: "F2", 120: "F1", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
        ]
        return keyMap[keyCode] ?? "?"
    }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var hotkey: HotkeyConfig {
        didSet {
            saveHotkey()
            NotificationCenter.default.post(name: .hotkeyChanged, object: hotkey)
        }
    }

    @Published var claudePath: String {
        didSet {
            UserDefaults.standard.set(claudePath, forKey: claudePathKey)
        }
    }

    private let hotkeyKey = "hotkey_config"
    private let claudePathKey = "claude_path"

    // Common locations where claude CLI might be installed
    static let defaultClaudePaths = [
        "~/.local/bin/claude",
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
        "~/.npm-global/bin/claude",
        "/usr/bin/claude"
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: hotkeyKey),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.hotkey = config
        } else {
            self.hotkey = .default
        }

        // Load saved path or auto-detect
        if let savedPath = UserDefaults.standard.string(forKey: claudePathKey), !savedPath.isEmpty {
            self.claudePath = savedPath
        } else {
            self.claudePath = SettingsManager.detectClaudePath() ?? ""
        }
    }

    private func saveHotkey() {
        if let data = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(data, forKey: hotkeyKey)
        }
    }

    static func detectClaudePath() -> String? {
        let fileManager = FileManager.default

        // Check common paths
        for path in defaultClaudePaths {
            let expandedPath = NSString(string: path).expandingTildeInPath
            if fileManager.isExecutableFile(atPath: expandedPath) {
                return expandedPath
            }
        }

        // Try using 'which' command
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        // Set up PATH
        var env = ProcessInfo.processInfo.environment
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if let path = env["PATH"] {
            env["PATH"] = "\(homeDir)/.local/bin:/usr/local/bin:/opt/homebrew/bin:" + path
        }
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {}

        return nil
    }

    func resolveClaudePath() -> String? {
        if !claudePath.isEmpty {
            let expandedPath = NSString(string: claudePath).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expandedPath) {
                return expandedPath
            }
        }
        return SettingsManager.detectClaudePath()
    }
}

extension Notification.Name {
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
}

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var isRecording = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Global Hotkey")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack {
                        HotkeyRecorder(
                            hotkey: $settings.hotkey,
                            isRecording: $isRecording
                        )

                        Button("Reset") {
                            settings.hotkey = .default
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    }

                    Text("Click the box and press your desired key combination")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Claude CLI Path")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack {
                        TextField("Path to claude", text: $settings.claudePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))

                        Button("Detect") {
                            if let detected = SettingsManager.detectClaudePath() {
                                settings.claudePath = detected
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))

                        Button("Browse") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = true
                            panel.canChooseDirectories = false
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                settings.claudePath = url.path
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    }

                    if settings.claudePath.isEmpty {
                        Text("Claude CLI not found. Install it or set the path manually.")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    } else if !FileManager.default.isExecutableFile(atPath: NSString(string: settings.claudePath).expandingTildeInPath) {
                        Text("File not found or not executable")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    } else {
                        Text("Claude CLI found")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    }
                }

                Spacer()
            }
            .padding(20)
        }
        .frame(width: 450, height: 280)
        .background(Color(NSColor.textBackgroundColor))
    }
}

struct HotkeyRecorder: View {
    @Binding var hotkey: HotkeyConfig
    @Binding var isRecording: Bool

    var body: some View {
        Button(action: { isRecording = true }) {
            Text(isRecording ? "Press keys..." : hotkey.displayString)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(isRecording ? .accentColor : .primary)
                .frame(minWidth: 120)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isRecording ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: isRecording ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .background(
            HotkeyRecorderHelper(isRecording: $isRecording, hotkey: $hotkey)
        )
    }
}

struct HotkeyRecorderHelper: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var hotkey: HotkeyConfig

    func makeNSView(context: Context) -> NSView {
        let view = HotkeyRecorderNSView()
        view.onKeyDown = { event in
            if isRecording {
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

                // Require at least one modifier
                if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
                    hotkey = HotkeyConfig(keyCode: event.keyCode, modifiers: modifiers.rawValue)
                    isRecording = false
                    return true
                }
            }
            return false
        }
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isRecording {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var view: HotkeyRecorderNSView?
    }
}

class HotkeyRecorderNSView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) != true {
            super.keyDown(with: event)
        }
    }
}

#Preview {
    SettingsView()
}
