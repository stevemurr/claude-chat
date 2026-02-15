import SwiftUI
import WebKit

@MainActor
class TiptapEditorViewModel: ObservableObject {
    weak var webView: WKWebView?
    @Published var isEditorReady = false

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
}
