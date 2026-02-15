import Foundation

// OpenAI-compatible API response types
struct OpenAIChatResponse: Decodable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Decodable {
    let index: Int
    let message: OpenAIMessage?
    let delta: OpenAIDelta?
    let finish_reason: String?
}

struct OpenAIMessage: Decodable {
    let role: String
    let content: String?
}

struct OpenAIDelta: Decodable {
    let role: String?
    let content: String?
}

struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [OpenAIRequestMessage]
    let stream: Bool
}

struct OpenAIRequestMessage: Encodable {
    let role: String
    let content: String
}

@MainActor
class ClaudeAPIService: ObservableObject, ClaudeServiceProtocol {
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var streamingText: String = ""
    @Published var isWorking: Bool = false

    private var currentTask: Task<Void, Never>?

    /// The API endpoint URL (configurable via Settings)
    var endpoint: URL {
        let urlString = SettingsManager.shared.apiEndpoint
        return URL(string: urlString) ?? URL(string: "http://macbook-pro-8.tail11899.ts.net:8080")!
    }

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

        let result = await runAPIStreaming(message: fullMessage, onUpdate: onUpdate)

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

    private func runAPIStreaming(
        message: String,
        onUpdate: @escaping (StreamUpdate) -> Void
    ) async -> Result<[String], ClaudeError> {
        let url = endpoint.appendingPathComponent("v1/chat/completions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = OpenAIChatRequest(
            model: "claude-cli",
            messages: [OpenAIRequestMessage(role: "user", content: message)],
            stream: true
        )

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            return .failure(ClaudeError(message: "Failed to encode request: \(error.localizedDescription)"))
        }

        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(ClaudeError(message: "Invalid response type"))
            }

            guard httpResponse.statusCode == 200 else {
                return .failure(ClaudeError(message: "API error: HTTP \(httpResponse.statusCode)"))
            }

            var allMessages: [String] = []
            var currentText = ""

            for try await line in bytes.lines {
                // SSE format: "data: {...}" or "data: [DONE]"
                guard line.hasPrefix("data: ") else { continue }

                let jsonString = String(line.dropFirst(6))

                if jsonString == "[DONE]" {
                    // Stream complete
                    if !currentText.isEmpty {
                        allMessages.append(currentText)
                        let textToSend = currentText
                        await MainActor.run {
                            onUpdate(StreamUpdate(text: textToSend, isComplete: true, isWorking: false))
                        }
                    }
                    break
                }

                guard let data = jsonString.data(using: .utf8) else { continue }

                do {
                    let chunk = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)

                    for choice in chunk.choices {
                        // Handle streaming delta
                        if let delta = choice.delta {
                            if let content = delta.content, !content.isEmpty {
                                currentText += content
                                let textToSend = currentText
                                await MainActor.run {
                                    onUpdate(StreamUpdate(text: textToSend, isComplete: false, isWorking: false))
                                }
                            }
                        }

                        // Handle finish reason
                        if let finishReason = choice.finish_reason, finishReason == "stop" {
                            if !currentText.isEmpty && (allMessages.isEmpty || allMessages.last != currentText) {
                                allMessages.append(currentText)
                                let textToSend = currentText
                                await MainActor.run {
                                    onUpdate(StreamUpdate(text: textToSend, isComplete: true, isWorking: false))
                                }
                            }
                        }
                    }
                } catch {
                    // Skip malformed chunks
                    continue
                }
            }

            // Add final message if not already added
            if !currentText.isEmpty && (allMessages.isEmpty || allMessages.last != currentText) {
                allMessages.append(currentText)
            }

            return .success(allMessages)
        } catch {
            if error is CancellationError {
                return .failure(ClaudeError(message: "Request cancelled"))
            }
            return .failure(ClaudeError(message: error.localizedDescription))
        }
    }

    func cancelRequest() {
        currentTask?.cancel()
        currentTask = nil
    }
}
