import Foundation

struct NoteUpdate {
    let dateKey: String
    let content: String
}

struct NoteUpdateParser {
    /// Parse note updates from Claude's response
    /// Returns extracted updates AND cleaned text (with tags removed) for display
    static func parse(_ text: String) -> (updates: [NoteUpdate], cleanedText: String) {
        print("[NoteUpdateParser] Parsing text (\(text.count) chars): \(text.prefix(500))...")
        // Pattern: <note-update date="YYYY-MM-DD">content</note-update>
        // Using [\s\S]*? for content to match across newlines (non-greedy)
        let pattern = #"<note-update\s+date="(\d{4}-\d{2}-\d{2})">([\s\S]*?)</note-update>"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return (updates: [], cleanedText: text)
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var updates: [NoteUpdate] = []

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let dateRange = Range(match.range(at: 1), in: text),
                  let contentRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let dateKey = String(text[dateRange])
            let content = String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            updates.append(NoteUpdate(dateKey: dateKey, content: content))
        }

        print("[NoteUpdateParser] Found \(updates.count) updates")
        for update in updates {
            print("[NoteUpdateParser] Update for \(update.dateKey): \(update.content.prefix(100))...")
        }

        // Remove the note-update tags from the display text
        let cleanedText = regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: nsText.length),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        return (updates: updates, cleanedText: cleanedText)
    }
}
