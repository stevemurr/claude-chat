import Foundation

/// Holds parsed content statistics for note preview cards
struct NoteContentStats {
    let completedTodos: Int
    let totalTodos: Int
    let bulletItems: [String]
    let linkCount: Int
    let videoCount: Int

    /// Human-readable todo progress (e.g., "2/5 ✓")
    var todoBadge: String? {
        guard totalTodos > 0 else { return nil }
        return "\(completedTodos)/\(totalTodos) ✓"
    }

    /// True if all todos are complete
    var allTodosComplete: Bool {
        totalTodos > 0 && completedTodos == totalTodos
    }

    /// True if some but not all todos are complete
    var partialTodosComplete: Bool {
        totalTodos > 0 && completedTodos > 0 && completedTodos < totalTodos
    }

    /// Footer text for link/video counts (e.g., "2 links · 1 video")
    var footerText: String? {
        var parts: [String] = []

        if linkCount > 0 {
            parts.append("\(linkCount) link\(linkCount == 1 ? "" : "s")")
        }
        if videoCount > 0 {
            parts.append("\(videoCount) video\(videoCount == 1 ? "" : "s")")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// True if there's any content to display
    var hasContent: Bool {
        totalTodos > 0 || !bulletItems.isEmpty || linkCount > 0 || videoCount > 0
    }

    /// Empty stats instance
    static let empty = NoteContentStats(
        completedTodos: 0,
        totalTodos: 0,
        bulletItems: [],
        linkCount: 0,
        videoCount: 0
    )
}
