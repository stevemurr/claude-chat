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

class SettingsManager: SharedSettingsManager {
    static let shared = SettingsManager()

    @Published var hotkey: HotkeyConfig {
        didSet {
            saveHotkey()
            NotificationCenter.default.post(name: .hotkeyChanged, object: hotkey)
        }
    }

    @Published var claudePath: String {
        didSet {
            UserDefaults.standard.set(claudePath, forKey: SettingsKeys.claudePath)
        }
    }

    // Common locations where claude CLI might be installed
    static let defaultClaudePaths = [
        "~/.local/bin/claude",
        "/usr/local/bin/claude",
        "/opt/homebrew/bin/claude",
        "~/.npm-global/bin/claude",
        "/usr/bin/claude"
    ]

    override init() {
        if let data = UserDefaults.standard.data(forKey: SettingsKeys.hotkeyConfig),
           let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            self.hotkey = config
        } else {
            self.hotkey = .default
        }

        // Load saved path or auto-detect
        if let savedPath = UserDefaults.standard.string(forKey: SettingsKeys.claudePath), !savedPath.isEmpty {
            self.claudePath = savedPath
        } else {
            self.claudePath = SettingsManager.detectClaudePath() ?? ""
        }

        super.init()
    }

    private func saveHotkey() {
        if let data = try? JSONEncoder().encode(hotkey) {
            UserDefaults.standard.set(data, forKey: SettingsKeys.hotkeyConfig)
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

        process.environment = ProcessEnvironment.environmentWithCLIPaths()

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
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 12)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
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

            // Service Toggle
            VStack(alignment: .leading, spacing: 8) {
                Text("Claude Service")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                Picker("", selection: $settings.useAPIService) {
                    Text("Local CLI").tag(false)
                    Text("API Server").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Text(settings.useAPIService
                    ? "Use HTTP API (works on iOS & remote)"
                    : "Use local Claude CLI (macOS only)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // CLI Path (only shown when using CLI)
            if !settings.useAPIService {
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
            }

            // API Settings (only shown when using API)
            if settings.useAPIService {
                VStack(alignment: .leading, spacing: 8) {
                    Text("API Endpoint")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    TextField("http://your-server:8080", text: $settings.apiEndpoint)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onChange(of: settings.apiEndpoint) { _ in
                            availableModels = []
                            modelFetchError = nil
                        }

                    Text("OpenAI-compatible endpoint (e.g., LiteLLM, Ollama)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("API Key")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    SecureField("Optional", text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .onChange(of: settings.apiKey) { _ in
                            availableModels = []
                            modelFetchError = nil
                        }

                    Text("Bearer token for authenticated endpoints")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack {
                        if !availableModels.isEmpty {
                            Picker("", selection: $settings.selectedModel) {
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .labelsHidden()
                        } else {
                            TextField("claude-cli", text: $settings.selectedModel)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                        }

                        Button(action: { fetchModels() }) {
                            if isFetchingModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                        .disabled(isFetchingModels)
                    }

                    if let error = modelFetchError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    } else {
                        Text("Select a model or click refresh to fetch from server")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Sync Server
            VStack(alignment: .leading, spacing: 8) {
                Text("Sync Server")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)

                TextField("http://your-server:8081", text: $settings.syncServerURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))

                Text("Server for syncing notes across devices")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .frame(width: 450, height: 500)
        .background(Color(NSColor.textBackgroundColor))
    }

    private func fetchModels() {
        isFetchingModels = true
        modelFetchError = nil

        let urlString = settings.apiEndpoint.hasSuffix("/")
            ? "\(settings.apiEndpoint)v1/models"
            : "\(settings.apiEndpoint)/v1/models"

        guard let url = URL(string: urlString) else {
            modelFetchError = "Invalid endpoint URL"
            isFetchingModels = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if !settings.apiKey.isEmpty {
            request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    await MainActor.run {
                        modelFetchError = "Invalid response"
                        isFetchingModels = false
                    }
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    await MainActor.run {
                        if httpResponse.statusCode == 401 {
                            modelFetchError = "Authentication required — check your API key"
                        } else {
                            modelFetchError = "Server returned HTTP \(httpResponse.statusCode)"
                        }
                        isFetchingModels = false
                    }
                    return
                }

                let modelsResponse = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
                let models = modelsResponse.data.map(\.id).sorted()

                await MainActor.run {
                    availableModels = models
                    if !models.contains(settings.selectedModel) {
                        settings.selectedModel = models.first ?? ""
                    }
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    modelFetchError = "Failed to fetch models: \(error.localizedDescription)"
                    isFetchingModels = false
                }
            }
        }
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
