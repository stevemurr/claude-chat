import SwiftUI

struct NotepadContentView: View {
    @ObservedObject var dailyNoteService: DailyNoteService

    @StateObject private var viewModel: TiptapEditorViewModel

    init(dailyNoteService: DailyNoteService) {
        self._dailyNoteService = ObservedObject(wrappedValue: dailyNoteService)
        self._viewModel = StateObject(wrappedValue: TiptapEditorViewModel(dailyNoteService: dailyNoteService))
    }

    var body: some View {
        TiptapEditorView(viewModel: viewModel)
            .background(Color.platformTextBackground)
            .onChange(of: dailyNoteService.currentNote.dateKey) { _, _ in
                viewModel.reloadFromNote()
            }
            .onReceive(NotificationCenter.default.publisher(for: .noteUpdated)) { notification in
                if let dateKey = notification.userInfo?["dateKey"] as? String,
                   dateKey == dailyNoteService.currentNote.dateKey {
                    viewModel.reloadFromNote()
                }
            }
    }
}
