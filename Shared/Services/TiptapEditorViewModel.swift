import SwiftUI
import WebKit

// MARK: - Mention Item

struct MentionItem: Codable {
    let type: String      // "note" or "group"
    let id: String        // dateKey for notes, groupId for groups
    let noteId: String?   // For groups: parent note dateKey
    let label: String     // Display title
    let preview: String?  // Optional preview text
}

// MARK: - Group Navigation State

struct GroupStackEntry: Identifiable, Equatable {
    let id: String
    let title: String
    var parentContent: String  // Content of the parent (full note or parent group) before entering
    var sourceNoteKey: String? // For cross-note mention navigation: the note we came from
}

@MainActor
class GroupNavigationState: ObservableObject {
    @Published var stack: [GroupStackEntry] = []

    var isInsideGroup: Bool {
        !stack.isEmpty
    }

    var currentGroupTitle: String? {
        stack.last?.title
    }

    var breadcrumbs: [String] {
        stack.map { $0.title }
    }

    func push(_ entry: GroupStackEntry) {
        stack.append(entry)
    }

    func pop() -> GroupStackEntry? {
        guard !stack.isEmpty else { return nil }
        return stack.removeLast()
    }

    func clear() {
        stack.removeAll()
        objectWillChange.send()
    }
}

// MARK: - Tiptap Editor View Model

@MainActor
class TiptapEditorViewModel: ObservableObject {
    weak var webView: WKWebView?
    @Published var isEditorReady = false
    @Published var groupNavigation = GroupNavigationState()

    private var dailyNoteService: DailyNoteService
    private var saveTimer: Timer?
    private var currentDateKey: String

    init(dailyNoteService: DailyNoteService) {
        self.dailyNoteService = dailyNoteService
        self.currentDateKey = dailyNoteService.currentNote.dateKey
    }

    func handleEditorReady() {
        isEditorReady = true
        reloadFromNote()
    }

    func handleContentChanged(_ markdown: String) {
        dailyNoteService.currentNote.content = markdown
        debounceSave()
    }

    func reloadFromNote() {
        let note = dailyNoteService.currentNote
        currentDateKey = note.dateKey

        // Always clear navigation when reloading the note
        groupNavigation.clear()

        guard isEditorReady, let webView = webView else { return }

        let content = note.content
        let escaped = content
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        webView.evaluateJavaScript("window.tiptap.setContent(`\(escaped)`)") { _, error in
            if let error = error {
                print("Failed to set Tiptap content: \(error)")
            }
        }
    }

    func focusEditor() {
        guard isEditorReady, let webView = webView else { return }
        webView.evaluateJavaScript("window.tiptap.focus()") { _, _ in }
    }

    func debounceSave() {
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dailyNoteService.saveCurrentNote()
            }
        }
    }

    func saveImmediately() {
        saveTimer?.invalidate()
        saveTimer = nil
        dailyNoteService.saveCurrentNote()
    }

    func noteDidChange() -> Bool {
        return currentDateKey != dailyNoteService.currentNote.dateKey
    }

    // MARK: - Group Navigation

    func navigateIntoGroup(id: String, title: String, sourceNoteKey: String? = nil) {
        guard isEditorReady, let webView = webView else { return }

        // Get the current content (parent content)
        webView.evaluateJavaScript("window.tiptap.getContent()") { [weak self] parentResult, error in
            guard let self = self else { return }

            if let error = error {
                print("Failed to get parent content: \(error)")
                return
            }

            let parentContent = parentResult as? String ?? ""

            // Extract the group's content from the parent markdown
            let groupContent = self.extractGroupContent(from: parentContent, groupId: id)

            // Push the parent content to the stack
            let entry = GroupStackEntry(id: id, title: title, parentContent: parentContent, sourceNoteKey: sourceNoteKey)
            self.groupNavigation.push(entry)

            // Load the group's content into the editor
            self.loadContent(groupContent)
        }
    }

    func navigateBack() {
        guard let entry = groupNavigation.pop() else { return }
        guard isEditorReady, let webView = webView else { return }

        // Get the current (edited) group content
        webView.evaluateJavaScript("window.tiptap.getContent()") { [weak self] result, error in
            guard let self = self else { return }

            let editedGroupContent = result as? String ?? ""

            // Update the group content in the parent markdown using string manipulation
            let updatedParent = self.updateGroupContent(
                in: entry.parentContent,
                groupId: entry.id,
                newContent: editedGroupContent
            )

            // Save to note and load the updated parent
            self.dailyNoteService.currentNote.content = updatedParent
            self.debounceSave()

            // If we came from a different note via mention, navigate back to that note
            if let sourceNoteKey = entry.sourceNoteKey,
               !self.groupNavigation.isInsideGroup,
               let date = DailyNote.dateFromKey(sourceNoteKey) {
                // Navigate back to the source note
                self.dailyNoteService.selectDate(date)
            } else {
                // Stay on current note, just load the parent content
                self.loadContent(updatedParent)
            }
        }
    }

    // Extract content between group markers
    private func extractGroupContent(from markdown: String, groupId: String) -> String {
        // Pattern: <!-- group:ID:TITLE -->\nCONTENT\n<!-- /group:ID -->
        let pattern = "<!--\\s*group:\(NSRegularExpression.escapedPattern(for: groupId)):[^>]*-->\\n?([\\s\\S]*?)\\n?<!--\\s*/group:\(NSRegularExpression.escapedPattern(for: groupId))\\s*-->"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: markdown, options: [], range: NSRange(markdown.startIndex..., in: markdown)),
              let contentRange = Range(match.range(at: 1), in: markdown) else {
            return ""
        }

        return String(markdown[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Replace content between group markers
    private func updateGroupContent(in markdown: String, groupId: String, newContent: String) -> String {
        // Pattern: <!-- group:ID:TITLE -->\nCONTENT\n<!-- /group:ID -->
        let pattern = "(<!--\\s*group:\(NSRegularExpression.escapedPattern(for: groupId)):[^>]*-->)\\n?[\\s\\S]*?\\n?(<!--\\s*/group:\(NSRegularExpression.escapedPattern(for: groupId))\\s*-->)"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return markdown
        }

        let range = NSRange(markdown.startIndex..., in: markdown)
        let replacement = "$1\n\(newContent)\n$2"

        return regex.stringByReplacingMatches(in: markdown, options: [], range: range, withTemplate: replacement)
    }

    private func loadContent(_ content: String) {
        guard let webView = webView else { return }

        let escaped = escapeForJS(content)
        webView.evaluateJavaScript("window.tiptap.setContent(`\(escaped)`)") { _, error in
            if let error = error {
                print("Failed to load content: \(error)")
            }
        }
    }

    private func escapeForJS(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }

    // MARK: - Mention Support

    func handleMentionItemsRequest(query: String) {
        let items = getMentionItems(query: query)
        sendMentionItemsToEditor(items)
    }

    func getMentionItems(query: String) -> [MentionItem] {
        var items: [MentionItem] = []

        // Add notes
        for note in dailyNoteService.allNotes {
            let preview = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first ?? ""
            let truncatedPreview = preview.count > 50 ? String(preview.prefix(50)) + "…" : preview

            items.append(MentionItem(
                type: "note",
                id: note.dateKey,
                noteId: nil,
                label: note.displayTitle,
                preview: truncatedPreview.isEmpty ? nil : truncatedPreview
            ))
        }

        // Add groups from all notes
        for note in dailyNoteService.allNotes {
            let groups = extractGroups(from: note.content)
            for group in groups {
                items.append(MentionItem(
                    type: "group",
                    id: group.id,
                    noteId: note.dateKey,
                    label: group.title,
                    preview: nil
                ))
            }
        }

        // Filter by query if provided
        if !query.isEmpty {
            let loweredQuery = query.lowercased()
            items = items.filter { $0.label.lowercased().contains(loweredQuery) }
        }

        // Limit results for performance
        return Array(items.prefix(20))
    }

    private func extractGroups(from content: String) -> [(id: String, title: String)] {
        var groups: [(id: String, title: String)] = []

        // Pattern: <!-- group:UUID:Title -->
        let pattern = "<!--\\s*group:([^:]+):([^>]+?)\\s*-->"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return groups
        }

        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        for match in matches {
            if let idRange = Range(match.range(at: 1), in: content),
               let titleRange = Range(match.range(at: 2), in: content) {
                let id = String(content[idRange])
                let title = String(content[titleRange]).trimmingCharacters(in: .whitespaces)
                groups.append((id: id, title: title))
            }
        }

        return groups
    }

    private func sendMentionItemsToEditor(_ items: [MentionItem]) {
        guard let webView = webView else { return }

        do {
            let jsonData = try JSONEncoder().encode(items)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                let js = "window.receiveMentionItems(\(jsonString))"
                webView.evaluateJavaScript(js) { _, error in
                    if let error = error {
                        print("Failed to send mention items: \(error)")
                    }
                }
            }
        } catch {
            print("Failed to encode mention items: \(error)")
        }
    }

    func handleOpenMention(data: [String: Any]) {
        guard let type = data["type"] as? String,
              let id = data["id"] as? String else {
            return
        }

        if type == "note" {
            navigateToNote(dateKey: id)
        } else if type == "group" {
            let noteId = data["noteId"] as? String
            navigateToGroup(noteId: noteId, groupId: id)
        }
    }

    private func navigateToNote(dateKey: String) {
        // Convert dateKey to Date and select it
        if let date = DailyNote.dateFromKey(dateKey) {
            dailyNoteService.selectDate(date)
        }
    }

    private func navigateToGroup(noteId: String?, groupId: String) {
        // Remember where we came from
        let sourceNoteKey = dailyNoteService.currentNote.dateKey

        // First navigate to the parent note if specified
        if let noteId = noteId, let date = DailyNote.dateFromKey(noteId) {
            dailyNoteService.selectDate(date)
        }

        // Then navigate into the group after a brief delay to let the note load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            // Get the group title from the content
            let content = self.dailyNoteService.currentNote.content
            let groups = self.extractGroups(from: content)
            if let group = groups.first(where: { $0.id == groupId }) {
                // Pass sourceNoteKey if we navigated from a different note
                let didChangeNote = sourceNoteKey != self.dailyNoteService.currentNote.dateKey
                self.navigateIntoGroup(id: groupId, title: group.title, sourceNoteKey: didChangeNote ? sourceNoteKey : nil)
            }
        }
    }
}
