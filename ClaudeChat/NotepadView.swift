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
        VStack(spacing: 0) {
            // Toolbar - simplified, no edit/preview toggle
            HStack(spacing: 12) {
                Text(noteService.currentNote.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Tiptap editor
            TiptapEditorView(viewModel: viewModel)
        }
        .background(Color(NSColor.textBackgroundColor))
        .onChange(of: noteService.currentNote.id) { _ in
            viewModel.reloadFromNote()
        }
    }
}

// MARK: - Note Sidebar

struct NoteSidebar: View {
    @ObservedObject var noteService: NoteService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Notes")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(noteService.notes) { note in
                        NoteRow(
                            note: note,
                            isSelected: note.id == noteService.currentNote.id,
                            onSelect: {
                                noteService.loadNote(note)
                            },
                            onDelete: {
                                noteService.deleteNote(note)
                            }
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer()
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }
}

struct NoteRow: View {
    let note: Note
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text(note.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                }

                Text(note.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : (isHovering ? Color(NSColor.controlBackgroundColor) : Color.clear))
        .cornerRadius(6)
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
