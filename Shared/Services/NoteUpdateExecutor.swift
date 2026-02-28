import Foundation

enum NoteUpdateError {
    case matchNotFound(String)
    case emptyMatch
}

struct NoteUpdateResult {
    let content: String
    let error: NoteUpdateError?
}

struct NoteUpdateExecutor {
    static func apply(
        existingContent: String,
        operation: NoteUpdateOperation,
        content: String,
        match: String?
    ) -> NoteUpdateResult {
        switch operation {
        case .append:
            if existingContent.isEmpty {
                return NoteUpdateResult(content: content, error: nil)
            }
            return NoteUpdateResult(content: existingContent + "\n" + content, error: nil)

        case .prepend:
            if existingContent.isEmpty {
                return NoteUpdateResult(content: content, error: nil)
            }
            return NoteUpdateResult(content: content + "\n" + existingContent, error: nil)

        case .replaceAll:
            return NoteUpdateResult(content: content, error: nil)

        case .replace:
            guard let match = match, !match.isEmpty else {
                return NoteUpdateResult(content: existingContent, error: .emptyMatch)
            }
            guard existingContent.contains(match) else {
                return NoteUpdateResult(content: existingContent, error: .matchNotFound(match))
            }
            if let range = existingContent.range(of: match) {
                let newContent = existingContent.replacingCharacters(in: range, with: content)
                return NoteUpdateResult(content: newContent, error: nil)
            }
            return NoteUpdateResult(content: existingContent, error: .matchNotFound(match))

        case .delete:
            guard let match = match, !match.isEmpty else {
                return NoteUpdateResult(content: existingContent, error: .emptyMatch)
            }
            guard let range = existingContent.range(of: match) else {
                return NoteUpdateResult(content: existingContent, error: .matchNotFound(match))
            }
            var newContent = existingContent.replacingCharacters(in: range, with: "")
            // Clean up triple newlines left by deletion
            while newContent.contains("\n\n\n") {
                newContent = newContent.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            }
            newContent = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
            return NoteUpdateResult(content: newContent, error: nil)

        case .insertAfter:
            guard let match = match, !match.isEmpty else {
                return NoteUpdateResult(content: existingContent, error: .emptyMatch)
            }
            guard let range = existingContent.range(of: match) else {
                return NoteUpdateResult(content: existingContent, error: .matchNotFound(match))
            }
            var newContent = existingContent
            newContent.insert(contentsOf: "\n" + content, at: range.upperBound)
            return NoteUpdateResult(content: newContent, error: nil)
        }
    }
}
