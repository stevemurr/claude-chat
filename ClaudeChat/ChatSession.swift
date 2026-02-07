import Foundation

struct ChatSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date
    var titleGenerated: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, messages, createdAt, updatedAt, titleGenerated
    }

    init(title: String = "New Chat", messages: [ChatMessage] = []) {
        self.id = UUID()
        self.title = title
        self.messages = messages
        self.createdAt = Date()
        self.updatedAt = Date()
        self.titleGenerated = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        messages = try container.decode([ChatMessage].self, forKey: .messages)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        titleGenerated = try container.decodeIfPresent(Bool.self, forKey: .titleGenerated) ?? false
    }

    mutating func addMessage(_ message: ChatMessage) {
        messages.append(message)
        updatedAt = Date()

        // Auto-generate title from first user message
        if title == "New Chat", message.role == .user {
            let content = message.content
            let maxLength = 40
            if content.count > maxLength {
                title = String(content.prefix(maxLength)) + "..."
            } else {
                title = content
            }
        }
    }
}

@MainActor
class ChatHistoryService: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var currentSession: ChatSession

    private let savePath: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ClaudeChat", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.savePath = appDir.appendingPathComponent("chat_history.json")
        self.currentSession = ChatSession()

        loadSessions()
    }

    func loadSessions() {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return }

        do {
            let data = try Data(contentsOf: savePath)
            sessions = try JSONDecoder().decode([ChatSession].self, from: data)
            sessions.sort { $0.updatedAt > $1.updatedAt }
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }

    func saveSessions() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: savePath)
        } catch {
            print("Failed to save sessions: \(error)")
        }
    }

    func saveCurrentSession() {
        guard !currentSession.messages.isEmpty else { return }

        if let index = sessions.firstIndex(where: { $0.id == currentSession.id }) {
            sessions[index] = currentSession
        } else {
            sessions.insert(currentSession, at: 0)
        }

        saveSessions()
    }

    func newSession() {
        saveCurrentSession()
        currentSession = ChatSession()
    }

    func loadSession(_ session: ChatSession) {
        saveCurrentSession()
        currentSession = session
    }

    func deleteSession(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        if currentSession.id == session.id {
            currentSession = ChatSession()
        }
        saveSessions()
    }

    func addMessageToCurrentSession(_ message: ChatMessage) {
        currentSession.addMessage(message)
        saveCurrentSession()
    }
}
