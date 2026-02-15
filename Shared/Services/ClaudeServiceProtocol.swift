import Foundation

struct ClaudeError: Error {
    let message: String
}

struct StreamUpdate {
    let text: String
    let isComplete: Bool  // true when this message block is complete
    let isWorking: Bool   // true when tools are running in background
}

/// Protocol defining the interface for Claude services (CLI or API-based)
@MainActor
protocol ClaudeServiceProtocol: ObservableObject {
    var isLoading: Bool { get }
    var lastError: String? { get }
    var streamingText: String { get }
    var isWorking: Bool { get }

    func sendMessage(
        _ message: String,
        noteContext: String?,
        continueConversation: Bool,
        onUpdate: @escaping (StreamUpdate) -> Void
    ) async -> [String]?

    func cancelRequest()
}
