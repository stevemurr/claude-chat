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

// MARK: - Markdown to Blocks Parser

extension Array where Element == Block {
    /// Parse a legacy markdown string into blocks for migration
    init(markdown: String) {
        var blocks: [Block] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Fenced code block
            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 } // skip closing ```
                blocks.append(Block(type: .code, content: codeLines.joined(separator: "\n")))
                continue
            }

            // Divider
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(Block(type: .divider))
                i += 1
                continue
            }

            // Headings (check ### before ## before #)
            if trimmed.hasPrefix("### ") {
                blocks.append(Block(type: .heading3, content: String(trimmed.dropFirst(4))))
                i += 1; continue
            }
            if trimmed.hasPrefix("## ") {
                blocks.append(Block(type: .heading2, content: String(trimmed.dropFirst(3))))
                i += 1; continue
            }
            if trimmed.hasPrefix("# ") {
                blocks.append(Block(type: .heading1, content: String(trimmed.dropFirst(2))))
                i += 1; continue
            }

            // Todo (checked)
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                blocks.append(Block(type: .todo, content: String(trimmed.dropFirst(6)), isChecked: true))
                i += 1; continue
            }
            // Todo (unchecked)
            if trimmed.hasPrefix("- [ ] ") {
                blocks.append(Block(type: .todo, content: String(trimmed.dropFirst(6)), isChecked: false))
                i += 1; continue
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(Block(type: .bulletList, content: String(trimmed.dropFirst(2))))
                i += 1; continue
            }

            // Numbered list
            if let dotIndex = trimmed.firstIndex(of: "."),
               trimmed.startIndex < dotIndex,
               trimmed[trimmed.startIndex..<dotIndex].allSatisfy({ $0.isNumber }),
               trimmed.index(after: dotIndex) < trimmed.endIndex,
               trimmed[trimmed.index(after: dotIndex)] == " " {
                let afterDotSpace = trimmed.index(dotIndex, offsetBy: 2)
                blocks.append(Block(type: .numberedList, content: String(trimmed[afterDotSpace...])))
                i += 1; continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let ql = lines[i].trimmingCharacters(in: .whitespaces)
                    if ql.hasPrefix("> ") {
                        quoteLines.append(String(ql.dropFirst(2)))
                        i += 1
                    } else { break }
                }
                blocks.append(Block(type: .quote, content: quoteLines.joined(separator: "\n")))
                continue
            }

            // Plain text
            blocks.append(Block(type: .text, content: line))
            i += 1
        }

        if blocks.isEmpty {
            blocks.append(Block())
        }

        self = blocks
    }
}

// MARK: - Blocks to Markdown Serializer

extension Array where Element == Block {
    func toMarkdown() -> String {
        var lines: [String] = []

        for (index, block) in self.enumerated() {
            switch block.type {
            case .text:
                lines.append(block.content)
            case .heading1:
                lines.append("# \(block.content)")
            case .heading2:
                lines.append("## \(block.content)")
            case .heading3:
                lines.append("### \(block.content)")
            case .bulletList:
                lines.append("- \(block.content)")
            case .numberedList:
                var ordinal = 1
                for j in stride(from: index - 1, through: 0, by: -1) {
                    if self[j].type == .numberedList { ordinal += 1 } else { break }
                }
                lines.append("\(ordinal). \(block.content)")
            case .todo:
                let check = block.isChecked ? "x" : " "
                lines.append("- [\(check)] \(block.content)")
            case .quote:
                for ql in block.content.components(separatedBy: "\n") {
                    lines.append("> \(ql)")
                }
            case .code:
                lines.append("```")
                lines.append(block.content)
                lines.append("```")
            case .divider:
                lines.append("---")
            case .group:
                // Groups are handled by Tiptap directly and serialized with HTML comments
                // This case is for completeness but shouldn't be reached in normal use
                lines.append("<!-- group -->")
                lines.append(block.content)
                lines.append("<!-- /group -->")
            }

            // Blank line between blocks, except consecutive same-type list items
            let nextType = index + 1 < self.count ? self[index + 1].type : nil
            let isConsecutiveList =
                (block.type == .bulletList && nextType == .bulletList) ||
                (block.type == .numberedList && nextType == .numberedList) ||
                (block.type == .todo && nextType == .todo)
            if !isConsecutiveList && index < self.count - 1 {
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }
}
