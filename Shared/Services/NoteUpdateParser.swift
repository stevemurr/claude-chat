import Foundation

enum NoteUpdateOperation: String {
    case append
    case prepend
    case replaceAll = "replace-all"
    case replace
    case delete
    case insertAfter = "insert-after"
}

struct NoteUpdate {
    let dateKey: String
    let operation: NoteUpdateOperation
    let content: String
    let match: String?
}

struct NoteUpdateParser {
    /// Parse note updates from Claude's response
    /// Returns extracted updates AND cleaned text (with tags removed) for display
    static func parse(_ text: String) -> (updates: [NoteUpdate], cleanedText: String) {
        var updates: [NoteUpdate] = []
        var cleanedText = text

        // Pattern 1: Self-closing tags (for delete)
        // <note-update date="..." op="..." match="..." />
        let selfClosingPattern = #"<note-update\s+date="(\d{4}-\d{2}-\d{2})"(?:\s+op="([^"]*)")?(?:\s+match="([^"]*)")?\s*/>"#

        if let selfClosingRegex = try? NSRegularExpression(pattern: selfClosingPattern, options: []) {
            let nsText = cleanedText as NSString
            let matches = selfClosingRegex.matches(in: cleanedText, range: NSRange(location: 0, length: nsText.length))

            for match in matches.reversed() {
                guard match.numberOfRanges >= 2,
                      let dateRange = Range(match.range(at: 1), in: cleanedText) else {
                    continue
                }

                let dateKey = String(cleanedText[dateRange])

                let opString: String? = match.range(at: 2).location != NSNotFound
                    ? Range(match.range(at: 2), in: cleanedText).map { String(cleanedText[$0]) }
                    : nil

                let matchString: String? = match.numberOfRanges >= 4 && match.range(at: 3).location != NSNotFound
                    ? Range(match.range(at: 3), in: cleanedText).map { String(cleanedText[$0]) }
                    : nil

                let operation = opString.flatMap { NoteUpdateOperation(rawValue: $0) } ?? .replaceAll

                updates.insert(NoteUpdate(dateKey: dateKey, operation: operation, content: "", match: matchString), at: 0)
            }

            // Remove self-closing tags from display text
            cleanedText = selfClosingRegex.stringByReplacingMatches(
                in: cleanedText,
                range: NSRange(location: 0, length: (cleanedText as NSString).length),
                withTemplate: ""
            )
        }

        // Pattern 2: Content tags (for everything else)
        // <note-update date="..." op="..." match="...">content</note-update>
        let contentPattern = #"<note-update\s+date="(\d{4}-\d{2}-\d{2})"(?:\s+op="([^"]*)")?(?:\s+match="([^"]*)")?>([\s\S]*?)</note-update>"#

        if let contentRegex = try? NSRegularExpression(pattern: contentPattern, options: []) {
            let nsText = cleanedText as NSString
            let matches = contentRegex.matches(in: cleanedText, range: NSRange(location: 0, length: nsText.length))

            for match in matches {
                guard match.numberOfRanges >= 5,
                      let dateRange = Range(match.range(at: 1), in: cleanedText),
                      let contentRange = Range(match.range(at: 4), in: cleanedText) else {
                    continue
                }

                let dateKey = String(cleanedText[dateRange])
                let content = String(cleanedText[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)

                let opString: String? = match.range(at: 2).location != NSNotFound
                    ? Range(match.range(at: 2), in: cleanedText).map { String(cleanedText[$0]) }
                    : nil

                let matchString: String? = match.range(at: 3).location != NSNotFound
                    ? Range(match.range(at: 3), in: cleanedText).map { String(cleanedText[$0]) }
                    : nil

                let operation = opString.flatMap { NoteUpdateOperation(rawValue: $0) } ?? .replaceAll

                updates.append(NoteUpdate(dateKey: dateKey, operation: operation, content: content, match: matchString))
            }

            // Remove content tags from display text
            cleanedText = contentRegex.stringByReplacingMatches(
                in: cleanedText,
                range: NSRange(location: 0, length: (cleanedText as NSString).length),
                withTemplate: ""
            )
        }

        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)

        return (updates: updates, cleanedText: cleanedText)
    }
}
