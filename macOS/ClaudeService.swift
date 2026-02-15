import Foundation

// Stream JSON message types from claude CLI
struct StreamMessage: Decodable {
    let type: String
    let content: String?
    let result: String?  // For "result" message type
    let message: MessageContent?

    struct MessageContent: Decodable {
        let content: [ContentBlock]?
    }

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}

@MainActor
class ClaudeService: ObservableObject, ClaudeServiceProtocol {
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var streamingText: String = ""
    @Published var isWorking: Bool = false  // Tools running in background

    private var currentProcess: Process?

    func sendMessage(
        _ message: String,
        noteContext: String? = nil,
        continueConversation: Bool = false,
        onUpdate: @escaping (StreamUpdate) -> Void
    ) async -> [String]? {
        isLoading = true
        isWorking = false
        lastError = nil
        streamingText = ""

        // Build full message with note context prepended
        let fullMessage: String
        if let context = noteContext, !context.isEmpty {
            fullMessage = """
            [The user has attached the following notes for reference. You can update these notes by including <note-update date="YYYY-MM-DD">new content</note-update> in your response, where YYYY-MM-DD matches the date shown in parentheses.]

            \(context)

            [User's message:]
            \(message)
            """
        } else {
            fullMessage = message
        }

        let result = await Task.detached(priority: .userInitiated) {
            await self.runClaudeStreaming(message: fullMessage, continueConversation: continueConversation, onUpdate: onUpdate)
        }.value

        switch result {
        case .success(let outputs):
            isLoading = false
            isWorking = false
            return outputs
        case .failure(let error):
            lastError = error.message
            isLoading = false
            isWorking = false
            return nil
        }
    }

    private nonisolated func runClaudeStreaming(message: String, continueConversation: Bool, onUpdate: @escaping (StreamUpdate) -> Void) async -> Result<[String], ClaudeError> {
        // Resolve claude path from settings
        guard let claudePath = SettingsManager.shared.resolveClaudePath() else {
            return .failure(ClaudeError(message: "Claude CLI not found. Please set the path in Settings."))
        }

        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: claudePath)

        var args = ["-p", message, "--output-format", "stream-json", "--verbose", "--tools", "default", "--dangerously-skip-permissions"]
        if continueConversation {
            args.insert("-c", at: 1)
        }
        process.arguments = args

        process.standardOutput = pipe
        process.standardError = errorPipe

        // Set up environment
        var env = ProcessInfo.processInfo.environment
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let localBin = "\(homeDir)/.local/bin"
        if let path = env["PATH"] {
            env["PATH"] = "\(localBin):/usr/local/bin:/opt/homebrew/bin:" + path
        } else {
            env["PATH"] = "\(localBin):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        }
        process.environment = env

        await MainActor.run {
            self.currentProcess = process
        }

        do {
            try process.run()

            let fileHandle = pipe.fileHandleForReading
            var allMessages: [String] = []
            var currentText = ""
            let decoder = JSONDecoder()

            // Read stream incrementally
            while true {
                let data = fileHandle.availableData
                if data.isEmpty {
                    if !process.isRunning { break }
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    continue
                }

                // Parse newline-delimited JSON
                if let str = String(data: data, encoding: .utf8) {
                    let lines = str.components(separatedBy: "\n")
                    for line in lines where !line.isEmpty {
                        if let lineData = line.data(using: .utf8),
                           let msg = try? decoder.decode(StreamMessage.self, from: lineData) {

                            // Handle assistant message with content
                            if msg.type == "assistant",
                               let content = msg.message?.content {
                                // If we have a previous message, save it
                                if !currentText.isEmpty {
                                    allMessages.append(currentText)
                                    let textToSend = currentText
                                    await MainActor.run {
                                        onUpdate(StreamUpdate(text: textToSend, isComplete: true, isWorking: false))
                                    }
                                }
                                // Start new message
                                currentText = ""
                                for block in content {
                                    if block.type == "text", let text = block.text {
                                        currentText = text
                                        let textToSend = currentText
                                        await MainActor.run {
                                            onUpdate(StreamUpdate(text: textToSend, isComplete: false, isWorking: false))
                                        }
                                    }
                                }
                            }

                            // Handle tool use - mark as working
                            if msg.type == "tool_use" || msg.type == "tool_use_block" {
                                // Save current message if any
                                if !currentText.isEmpty {
                                    allMessages.append(currentText)
                                    let textToSend = currentText
                                    await MainActor.run {
                                        onUpdate(StreamUpdate(text: textToSend, isComplete: true, isWorking: true))
                                    }
                                    currentText = ""
                                } else {
                                    await MainActor.run {
                                        onUpdate(StreamUpdate(text: "", isComplete: false, isWorking: true))
                                    }
                                }
                            }

                            // Handle tool result - still working until next assistant message
                            if msg.type == "tool_result" {
                                await MainActor.run {
                                    onUpdate(StreamUpdate(text: "", isComplete: false, isWorking: true))
                                }
                            }

                            // Handle result message
                            if msg.type == "result", let resultText = msg.result {
                                if !resultText.isEmpty {
                                    currentText = resultText
                                    allMessages.append(currentText)
                                }
                                let textToSend = currentText
                                await MainActor.run {
                                    onUpdate(StreamUpdate(text: textToSend, isComplete: true, isWorking: false))
                                }
                            }
                        }
                    }
                }
            }

            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                return .failure(ClaudeError(message: errorString))
            }

            // Add final message if not already added
            if !currentText.isEmpty && (allMessages.isEmpty || allMessages.last != currentText) {
                allMessages.append(currentText)
            }

            return .success(allMessages)
        } catch {
            return .failure(ClaudeError(message: error.localizedDescription))
        }
    }

    func cancelRequest() {
        currentProcess?.terminate()
    }
}
