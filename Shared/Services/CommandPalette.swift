import Foundation

// MARK: - Static Visibility State (for AppDelegate escape key check)

enum CommandPaletteState {
    static var isVisible = false
}

// MARK: - Model

enum CommandPaletteItemType {
    case dailyNote
    case chat
    case action
}

enum CommandPaletteAction: String {
    case newNote = "newNote"
    case newChat = "newChat"
}

struct CommandPaletteItem: Identifiable {
    let id: String
    let type: CommandPaletteItemType
    let title: String
    let preview: String
    let timestamp: Date
    var score: Double
    let dailyNote: DailyNote?
    let session: ChatSession?
    let action: CommandPaletteAction?

    init(dailyNote: DailyNote, score: Double = 0) {
        self.id = dailyNote.dateKey
        self.type = .dailyNote
        self.title = dailyNote.displayTitle
        self.preview = Self.makePreview(from: dailyNote.content)
        self.timestamp = dailyNote.updatedAt
        self.score = score
        self.dailyNote = dailyNote
        self.session = nil
        self.action = nil
    }

    init(session: ChatSession, score: Double = 0) {
        self.id = session.id.uuidString
        self.type = .chat
        self.title = session.title
        self.preview = Self.makePreview(from: session.messages.last?.content ?? "")
        self.timestamp = session.updatedAt
        self.score = score
        self.dailyNote = nil
        self.session = session
        self.action = nil
    }

    init(action: CommandPaletteAction, title: String, preview: String) {
        self.id = UUID().uuidString
        self.type = .action
        self.title = title
        self.preview = preview
        self.timestamp = Date()
        self.score = 100 // Actions always sort first
        self.dailyNote = nil
        self.session = nil
        self.action = action
    }

    private static func makePreview(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 80 {
            return String(trimmed.prefix(80)) + "..."
        }
        return trimmed.isEmpty ? "" : trimmed
    }
}

// MARK: - Fuzzy Search

func fuzzyMatch(query: String, target: String) -> Double? {
    let query = query.lowercased()
    let target = target.lowercased()

    guard !query.isEmpty, !target.isEmpty else { return nil }

    // For single-character queries, require substring match at a word boundary
    if query.count == 1 {
        guard let idx = target.firstIndex(of: query.first!) else { return nil }
        if idx == target.startIndex { return 1.0 }
        let prev = target[target.index(before: idx)]
        if prev == " " || prev == "-" || prev == "_" || prev == "/" {
            return 0.8
        }
        return nil // Single char must match at word boundary
    }

    // Check for substring containment first — strong signal
    if target.contains(query) {
        // Exact substring gets high score, boosted if at start
        let range = target.range(of: query)!
        let position = target.distance(from: target.startIndex, to: range.lowerBound)
        let lengthRatio = Double(query.count) / Double(target.count)
        let positionBonus = position == 0 ? 2.0 : (position < 5 ? 1.0 : 0.0)
        return 3.0 + lengthRatio * 2.0 + positionBonus
    }

    // Fuzzy sequential match with gap penalties
    var queryIndex = query.startIndex
    var targetIndex = target.startIndex
    var score: Double = 0
    var lastMatchPosition: Int = -1
    var totalGap: Int = 0

    while queryIndex < query.endIndex && targetIndex < target.endIndex {
        if query[queryIndex] == target[targetIndex] {
            let currentPosition = target.distance(from: target.startIndex, to: targetIndex)
            var bonus: Double = 1.0

            // Consecutive match bonus
            if lastMatchPosition >= 0 && currentPosition == lastMatchPosition + 1 {
                bonus += 3.0
            } else if lastMatchPosition >= 0 {
                // Gap penalty
                let gap = currentPosition - lastMatchPosition - 1
                totalGap += gap
            }

            // Start-of-word bonus
            if targetIndex == target.startIndex {
                bonus += 3.0
            } else {
                let prev = target[target.index(before: targetIndex)]
                if prev == " " || prev == "-" || prev == "_" || prev == "/" {
                    bonus += 2.0
                }
            }

            // Prefix position bonus
            if currentPosition < 5 {
                bonus += Double(5 - currentPosition) * 0.5
            }

            score += bonus
            lastMatchPosition = currentPosition
            queryIndex = query.index(after: queryIndex)
        }
        targetIndex = target.index(after: targetIndex)
    }

    // All query characters must be found
    guard queryIndex == query.endIndex else { return nil }

    // Apply gap penalty — large gaps mean poor match quality
    let gapPenalty = Double(totalGap) * 0.3
    score = max(score - gapPenalty, 0.1)

    // Normalize: reward when query covers more of the target
    let coverageRatio = Double(query.count) / Double(target.count)
    let normalized = score * (0.5 + coverageRatio * 0.5) / max(Double(target.count), 1.0)

    // Minimum threshold to avoid weak scattered matches
    let minThreshold = 0.05
    return normalized >= minThreshold ? normalized : nil
}

// MARK: - Service

@MainActor
class CommandPaletteService: ObservableObject {
    @Published var query: String = ""
    @Published var results: [CommandPaletteItem] = []
    @Published var selectedIndex: Int = 0
    @Published var isVisible: Bool = false

    private var dailyNoteService: DailyNoteService?
    private var historyService: ChatHistoryService?

    private let actions: [CommandPaletteItem] = [
        CommandPaletteItem(action: .newChat, title: "New Chat", preview: "Start a new conversation"),
        CommandPaletteItem(action: .newNote, title: "Today's Note", preview: "Open today's daily note"),
    ]

    func configure(dailyNoteService: DailyNoteService, historyService: ChatHistoryService? = nil) {
        self.dailyNoteService = dailyNoteService
        self.historyService = historyService
    }

    func show() {
        query = ""
        selectedIndex = 0
        isVisible = true
        CommandPaletteState.isVisible = true
        computeRecentItems()
    }

    func dismiss() {
        isVisible = false
        CommandPaletteState.isVisible = false
        query = ""
        results = []
    }

    func search() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            computeRecentItems()
            return
        }

        let loweredQuery = query.lowercased()

        // Filter actions by substring match on title
        let matchingActions = actions.filter {
            $0.title.lowercased().contains(loweredQuery)
        }

        // Search daily notes and chats
        var searchItems: [CommandPaletteItem] = []

        // Search daily notes: fuzzy on display title, substring-only on content
        if let dailyNoteService = dailyNoteService {
            for note in dailyNoteService.allNotes {
                let titleScore = fuzzyMatch(query: query, target: note.displayTitle)
                let contentHit = note.content.lowercased().contains(loweredQuery) ? 0.5 : 0.0
                let bestScore = max(titleScore ?? 0, contentHit)
                if bestScore > 0 {
                    searchItems.append(CommandPaletteItem(dailyNote: note, score: bestScore))
                }
            }
        }

        // Search chat sessions: fuzzy on title, substring-only on last message
        if let historyService = historyService {
            for session in historyService.sessions {
                let titleScore = fuzzyMatch(query: query, target: session.title)
                let lastMessage = session.messages.last?.content ?? ""
                let messageHit = lastMessage.lowercased().contains(loweredQuery) ? 0.5 : 0.0
                let bestScore = max(titleScore ?? 0, messageHit)
                if bestScore > 0 {
                    searchItems.append(CommandPaletteItem(session: session, score: bestScore))
                }
            }
        }

        // Sort search results by score descending, cap at 20
        searchItems.sort { $0.score > $1.score }
        searchItems = Array(searchItems.prefix(20))

        // Actions always appear first
        results = matchingActions + searchItems
        selectedIndex = 0
    }

    func moveUp() {
        guard !results.isEmpty else { return }
        if selectedIndex <= 0 {
            selectedIndex = results.count - 1
        } else {
            selectedIndex -= 1
        }
    }

    func moveDown() {
        guard !results.isEmpty else { return }
        if selectedIndex >= results.count - 1 {
            selectedIndex = 0
        } else {
            selectedIndex += 1
        }
    }

    private func computeRecentItems() {
        var recentItems: [CommandPaletteItem] = []

        if let dailyNoteService = dailyNoteService {
            for note in dailyNoteService.allNotes {
                recentItems.append(CommandPaletteItem(dailyNote: note))
            }
        }

        if let historyService = historyService {
            for session in historyService.sessions {
                recentItems.append(CommandPaletteItem(session: session))
            }
        }

        // Sort by most recently updated
        recentItems.sort { $0.timestamp > $1.timestamp }
        recentItems = Array(recentItems.prefix(20))

        results = recentItems
        selectedIndex = 0
    }
}
