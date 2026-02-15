import SwiftUI
import WebKit

// MARK: - Group Navigation State

struct GroupStackEntry: Identifiable, Equatable {
    let id: String
    let title: String
    var parentContent: String  // Content of the parent (full note or parent group) before entering
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

    func navigateIntoGroup(id: String, title: String) {
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
            let entry = GroupStackEntry(id: id, title: title, parentContent: parentContent)
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
            self.loadContent(updatedParent)
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
}
