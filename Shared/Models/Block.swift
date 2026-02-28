import Foundation

// MARK: - Block Type

enum BlockType: String, Codable, CaseIterable {
    case text
    case heading1
    case heading2
    case heading3
    case bulletList
    case numberedList
    case todo
    case quote
    case code
    case divider
    case group
}

// MARK: - Block Model

struct Block: Identifiable, Codable, Equatable {
    let id: UUID
    var type: BlockType
    var content: String
    var isChecked: Bool

    init(
        id: UUID = UUID(),
        type: BlockType = .text,
        content: String = "",
        isChecked: Bool = false
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.isChecked = isChecked
    }
}
