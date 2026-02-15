import SwiftUI

// MARK: - Group Navigation Header

struct GroupNavigationHeader: View {
    @ObservedObject var viewModel: TiptapEditorViewModel
    @ObservedObject var groupNavigation: GroupNavigationState

    var body: some View {
        if groupNavigation.isInsideGroup {
            HStack(spacing: 0) {
                // Native-style back button
                Button(action: {
                    viewModel.navigateBack()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                        if groupNavigation.stack.count == 1 {
                            Text("Note")
                                .font(.system(size: 13))
                        } else if groupNavigation.stack.count > 1 {
                            // Show parent group name
                            Text(groupNavigation.stack[groupNavigation.stack.count - 2].title)
                                .font(.system(size: 13))
                                .lineLimit(1)
                        }
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                // Current group title (centered)
                Text(groupNavigation.currentGroupTitle ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                // Placeholder for symmetry (same width as back button area)
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .medium))
                    Text("Note")
                        .font(.system(size: 13))
                }
                .opacity(0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
    }
}

// MARK: - Notepad Content View

struct NotepadContentView: View {
    @ObservedObject var dailyNoteService: DailyNoteService

    @StateObject private var viewModel: TiptapEditorViewModel

    init(dailyNoteService: DailyNoteService) {
        self._dailyNoteService = ObservedObject(wrappedValue: dailyNoteService)
        self._viewModel = StateObject(wrappedValue: TiptapEditorViewModel(dailyNoteService: dailyNoteService))
    }

    var body: some View {
        VStack(spacing: 0) {
            GroupNavigationHeader(viewModel: viewModel, groupNavigation: viewModel.groupNavigation)

            TiptapEditorView(viewModel: viewModel)
                .background(Color.platformTextBackground)
        }
        .onChange(of: dailyNoteService.currentNote.dateKey) { _, _ in
            // Clear navigation stack when switching notes
            viewModel.groupNavigation.clear()
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
