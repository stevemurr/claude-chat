import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    // Tool result support (for collapsible display)
    let toolName: String?
    let toolOutput: String?

    var isToolResult: Bool {
        toolName != nil
    }

    init(role: MessageRole, content: String, toolName: String? = nil, toolOutput: String? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.toolName = toolName
        self.toolOutput = toolOutput
    }
}
