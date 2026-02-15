import Foundation

struct DailyNote: Identifiable, Codable {
    let dateKey: String        // "yyyy-MM-dd" - serves as id
    var content: String
    var blocks: [Block]?
    var updatedAt: Date
    var chatMessages: [ChatMessage]      // Per-note chat history
    var conversationStarted: Bool        // For ClaudeService -c flag

    var id: String { dateKey }

    /// Check if the note has meaningful content
    var hasContent: Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return true }
        if let blocks = blocks,
           blocks.contains(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return true
        }
        return false
    }

    /// Formatted date for display (e.g., "February 13, 2026")
    var displayTitle: String {
        guard let date = Self.dateFromKey(dateKey) else { return dateKey }
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Short display title (e.g., "Feb 13")
    var shortDisplayTitle: String {
        guard let date = Self.dateFromKey(dateKey) else { return dateKey }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    init(dateKey: String, content: String = "", blocks: [Block]? = nil) {
        self.dateKey = dateKey
        self.content = content
        self.blocks = blocks ?? [Block()]
        self.updatedAt = Date()
        self.chatMessages = []
        self.conversationStarted = false
    }

    init(date: Date, content: String = "", blocks: [Block]? = nil) {
        self.dateKey = Self.keyFromDate(date)
        self.content = content
        self.blocks = blocks ?? [Block()]
        self.updatedAt = Date()
        self.chatMessages = []
        self.conversationStarted = false
    }

    // MARK: - Codable (Backward Compatible)

    enum CodingKeys: String, CodingKey {
        case dateKey, content, blocks, updatedAt, chatMessages, conversationStarted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dateKey = try container.decode(String.self, forKey: .dateKey)
        content = try container.decode(String.self, forKey: .content)
        blocks = try container.decodeIfPresent([Block].self, forKey: .blocks)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        chatMessages = try container.decodeIfPresent([ChatMessage].self, forKey: .chatMessages) ?? []
        conversationStarted = try container.decodeIfPresent(Bool.self, forKey: .conversationStarted) ?? false
    }

    // MARK: - Date Key Helpers

    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    static func keyFromDate(_ date: Date) -> String {
        dateKeyFormatter.string(from: date)
    }

    static func dateFromKey(_ key: String) -> Date? {
        dateKeyFormatter.date(from: key)
    }

    // MARK: - Content Helpers

    /// Get blocks, lazily parsing from content for legacy notes
    mutating func resolveBlocks() -> [Block] {
        if let existing = blocks, !existing.isEmpty {
            return existing
        }
        let parsed = [Block](markdown: content)
        blocks = parsed
        return parsed
    }

    /// Sync the content string from blocks
    mutating func syncContentFromBlocks() {
        guard let blocks = blocks else { return }
        content = blocks.toMarkdown()
    }

    /// Ensure content is populated from blocks
    mutating func ensureContentPopulated() {
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let blocks = blocks, !blocks.isEmpty {
            content = blocks.toMarkdown()
        }
    }
}
