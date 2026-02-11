import Foundation

struct Note: Identifiable, Codable {
    let id: UUID
    var title: String
    var content: String
    var blocks: [Block]?
    let createdAt: Date
    var updatedAt: Date
    var titleGenerated: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, content, blocks, createdAt, updatedAt, titleGenerated
    }

    init(title: String = "Untitled", content: String = "") {
        self.id = UUID()
        self.title = title
        self.content = content
        self.blocks = [Block()]
        self.createdAt = Date()
        self.updatedAt = Date()
        self.titleGenerated = false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        blocks = try container.decodeIfPresent([Block].self, forKey: .blocks)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        titleGenerated = try container.decodeIfPresent(Bool.self, forKey: .titleGenerated) ?? false
    }

    /// Get blocks, lazily parsing from content for legacy notes
    mutating func resolveBlocks() -> [Block] {
        if let existing = blocks, !existing.isEmpty {
            return existing
        }
        let parsed = [Block](markdown: content)
        blocks = parsed
        return parsed
    }

    /// Sync the content string from blocks (call before saving)
    mutating func syncContentFromBlocks() {
        guard let blocks = blocks else { return }
        content = blocks.toMarkdown()
        updateTitleFromBlocks()
    }

    /// Auto-generate title from the first non-empty block
    mutating func updateTitleFromBlocks() {
        guard let blocks = blocks else {
            updateTitleFromContent()
            return
        }

        guard let firstBlock = blocks.first(where: {
            !$0.content.trimmingCharacters(in: .whitespaces).isEmpty
        }) else {
            title = "Untitled"
            return
        }

        let cleaned = firstBlock.content.trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty {
            title = "Untitled"
        } else if cleaned.count > 40 {
            title = String(cleaned.prefix(40)) + "..."
        } else {
            title = cleaned
        }
    }

    /// Legacy title generation from content string
    mutating func updateTitleFromContent() {
        let lines = content.components(separatedBy: .newlines)
        guard let firstLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            title = "Untitled"
            return
        }

        var cleaned = firstLine
        while cleaned.hasPrefix("#") {
            cleaned = String(cleaned.dropFirst())
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        if cleaned.isEmpty {
            title = "Untitled"
        } else if cleaned.count > 40 {
            title = String(cleaned.prefix(40)) + "..."
        } else {
            title = cleaned
        }
    }

    /// Ensure content is populated from blocks for legacy notes
    mutating func ensureContentPopulated() {
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let blocks = blocks, !blocks.isEmpty {
            content = blocks.toMarkdown()
        }
    }

    /// Check if the note is effectively empty
    var isEmpty: Bool {
        let contentEmpty = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !contentEmpty { return false }
        // Also check blocks for legacy notes where content may not be synced yet
        if let blocks = blocks,
           blocks.contains(where: { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return false
        }
        return true
    }
}
