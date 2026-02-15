import Foundation

/// Stateless utility for parsing note content into statistics
enum NoteContentParser {

    /// Parse markdown content into statistics for preview cards
    static func parse(_ content: String) -> NoteContentStats {
        let lines = content.components(separatedBy: .newlines)

        var completedTodos = 0
        var uncheckedTodos = 0
        var bulletItems: [String] = []
        var linkCount = 0
        var videoCount = 0

        // Regex patterns
        let checkedTodoPattern = #"^[-*]\s*\[[xX]\]\s+(.+)$"#
        let uncheckedTodoPattern = #"^[-*]\s*\[\s\]\s+(.+)$"#
        let bulletPattern = #"^[-*]\s+(?!\[[ xX]\])(.+)$"#
        let linkPattern = #"\[([^\]]+)\]\(([^)]+)\)"#

        let checkedTodoRegex = try? NSRegularExpression(pattern: checkedTodoPattern)
        let uncheckedTodoRegex = try? NSRegularExpression(pattern: uncheckedTodoPattern)
        let bulletRegex = try? NSRegularExpression(pattern: bulletPattern)
        let linkRegex = try? NSRegularExpression(pattern: linkPattern)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let range = NSRange(trimmed.startIndex..., in: trimmed)

            // Check for checked todo
            if let match = checkedTodoRegex?.firstMatch(in: trimmed, range: range) {
                completedTodos += 1
                // Extract todo text for bullet preview
                if bulletItems.count < 3, let textRange = Range(match.range(at: 1), in: trimmed) {
                    let text = String(trimmed[textRange])
                    bulletItems.append(truncate(text, to: 40))
                }
                continue
            }

            // Check for unchecked todo
            if let match = uncheckedTodoRegex?.firstMatch(in: trimmed, range: range) {
                uncheckedTodos += 1
                // Extract todo text for bullet preview
                if bulletItems.count < 3, let textRange = Range(match.range(at: 1), in: trimmed) {
                    let text = String(trimmed[textRange])
                    bulletItems.append(truncate(text, to: 40))
                }
                continue
            }

            // Check for regular bullet (not a todo)
            if let match = bulletRegex?.firstMatch(in: trimmed, range: range) {
                if bulletItems.count < 3, let textRange = Range(match.range(at: 1), in: trimmed) {
                    let text = String(trimmed[textRange])
                    bulletItems.append(truncate(text, to: 40))
                }
            }
        }

        // Count links and detect videos
        if let linkRegex = linkRegex {
            let fullRange = NSRange(content.startIndex..., in: content)
            let matches = linkRegex.matches(in: content, range: fullRange)

            for match in matches {
                linkCount += 1

                // Check if link is a video
                if let urlRange = Range(match.range(at: 2), in: content) {
                    let url = String(content[urlRange]).lowercased()
                    if isVideoURL(url) {
                        videoCount += 1
                    }
                }
            }
        }

        return NoteContentStats(
            completedTodos: completedTodos,
            totalTodos: completedTodos + uncheckedTodos,
            bulletItems: bulletItems,
            linkCount: linkCount,
            videoCount: videoCount
        )
    }

    /// Check if a URL is a video link
    private static func isVideoURL(_ url: String) -> Bool {
        let videoPatterns = [
            "youtube.com",
            "youtu.be",
            "vimeo.com",
            ".mp4",
            ".mov",
            ".webm",
            ".avi",
            "dailymotion.com",
            "twitch.tv"
        ]
        return videoPatterns.contains { url.contains($0) }
    }

    /// Truncate text to a maximum length with ellipsis
    private static func truncate(_ text: String, to maxLength: Int) -> String {
        if text.count <= maxLength {
            return text
        }
        let endIndex = text.index(text.startIndex, offsetBy: maxLength - 1)
        return String(text[..<endIndex]) + "…"
    }
}
