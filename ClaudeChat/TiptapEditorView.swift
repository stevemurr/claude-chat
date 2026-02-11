import SwiftUI
import WebKit
import Combine

// MARK: - TiptapEditorViewModel

@MainActor
class TiptapEditorViewModel: ObservableObject {
    weak var webView: WKWebView?
    @Published var isEditorReady = false

    private var noteService: NoteService
    private var titleService: TitleService?
    private var saveTimer: Timer?
    private var currentNoteID: UUID?
    private var titleGenerationInFlight = false

    init(noteService: NoteService, titleService: TitleService? = nil) {
        self.noteService = noteService
        self.titleService = titleService
        self.currentNoteID = noteService.currentNote.id
    }

    func handleEditorReady() {
        isEditorReady = true
        reloadFromNote()
    }

    func handleContentChanged(_ markdown: String) {
        noteService.currentNote.content = markdown
        noteService.currentNote.updateTitleFromContent()
        debounceSave()

        // Trigger AI title generation when content is long enough
        if let titleService = titleService,
           markdown.count > 50,
           !noteService.currentNote.titleGenerated,
           !titleGenerationInFlight {
            titleGenerationInFlight = true
            let content = markdown
            Task {
                if let title = await titleService.generateTitle(for: content) {
                    noteService.currentNote.title = title
                    noteService.currentNote.titleGenerated = true
                    debounceSave()
                }
                titleGenerationInFlight = false
            }
        }
    }

    func reloadFromNote() {
        currentNoteID = noteService.currentNote.id
        titleGenerationInFlight = false

        // Ensure content is populated from blocks for legacy notes
        noteService.currentNote.ensureContentPopulated()

        guard isEditorReady, let webView = webView else { return }

        let content = noteService.currentNote.content
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
                self?.noteService.saveCurrentNote()
            }
        }
    }

    func saveImmediately() {
        saveTimer?.invalidate()
        saveTimer = nil
        noteService.saveCurrentNote()
    }

    /// Returns true if the note has changed and needs a reload
    func noteDidChange() -> Bool {
        return currentNoteID != noteService.currentNote.id
    }
}

// MARK: - TiptapEditorView

struct TiptapEditorView: NSViewRepresentable {
    @ObservedObject var viewModel: TiptapEditorViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        // Register message handlers
        userContentController.add(context.coordinator, name: "contentChanged")
        userContentController.add(context.coordinator, name: "editorReady")

        config.userContentController = userContentController

        // Allow file access for loading bundle.js
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.wantsLayer = true
        webView.layer?.drawsAsynchronously = true
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")

        // Load the HTML from app bundle
        if let htmlURL = Bundle.main.url(forResource: "tiptap-editor", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }

        viewModel.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if viewModel.noteDidChange() {
            viewModel.reloadFromNote()
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKScriptMessageHandler {
        let viewModel: TiptapEditorViewModel

        init(viewModel: TiptapEditorViewModel) {
            self.viewModel = viewModel
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            Task { @MainActor in
                switch message.name {
                case "editorReady":
                    viewModel.handleEditorReady()

                case "contentChanged":
                    if let markdown = message.body as? String {
                        viewModel.handleContentChanged(markdown)
                    }

                default:
                    break
                }
            }
        }
    }
}
