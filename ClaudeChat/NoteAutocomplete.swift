import SwiftUI

struct NoteAutocompletePopup: View {
    @ObservedObject var noteService: NoteService
    let query: String
    @Binding var selectedIndex: Int
    let onSelect: (Note) -> Void
    let onDismiss: () -> Void

    private var filteredNotes: [Note] {
        let results = noteService.searchNotes(query: query)
        return Array(results.prefix(5))
    }

    var body: some View {
        let notes = filteredNotes

        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                    AutocompleteRow(
                        note: note,
                        isSelected: index == selectedIndex
                    )
                    .onTapGesture {
                        onSelect(note)
                    }

                    if index < notes.count - 1 {
                        Divider()
                            .padding(.horizontal, 8)
                    }
                }
            }
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: -4)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }
}

struct AutocompleteRow: View {
    let note: Note
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text(contentPreview)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    private var contentPreview: String {
        let trimmed = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 50 {
            return String(trimmed.prefix(50)) + "..."
        }
        return trimmed.isEmpty ? "Empty note" : trimmed
    }
}
