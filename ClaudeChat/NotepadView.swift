import SwiftUI

struct NotepadContentView: View {
    @ObservedObject var noteService: NoteService
    var titleService: TitleService?

    @StateObject private var viewModel: TiptapEditorViewModel

    init(noteService: NoteService, titleService: TitleService? = nil) {
        self._noteService = ObservedObject(wrappedValue: noteService)
        self.titleService = titleService
        self._viewModel = StateObject(wrappedValue: TiptapEditorViewModel(noteService: noteService, titleService: titleService))
    }

    var body: some View {
        TiptapEditorView(viewModel: viewModel)
            .background(Color(NSColor.textBackgroundColor))
            .onChange(of: noteService.currentNote.id) { _ in
                viewModel.reloadFromNote()
            }
    }
}
