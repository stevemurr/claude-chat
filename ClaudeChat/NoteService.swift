import Foundation

@MainActor
class NoteService: ObservableObject {
    @Published var notes: [Note] = []
    @Published var currentNote: Note

    private let savePath: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ClaudeChat", isDirectory: true)

        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)

        self.savePath = appDir.appendingPathComponent("notes.json")
        self.currentNote = Note()

        loadNotes()
    }

    func loadNotes() {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return }

        do {
            let data = try Data(contentsOf: savePath)
            notes = try JSONDecoder().decode([Note].self, from: data)
            notes.sort { $0.updatedAt > $1.updatedAt }
        } catch {
            print("Failed to load notes: \(error)")
        }
    }

    func saveNotes() {
        do {
            let data = try JSONEncoder().encode(notes)
            try data.write(to: savePath)
        } catch {
            print("Failed to save notes: \(error)")
        }
    }

    func saveCurrentNote() {
        // Don't save completely empty notes
        guard !currentNote.isEmpty else { return }

        currentNote.updatedAt = Date()

        if let index = notes.firstIndex(where: { $0.id == currentNote.id }) {
            notes[index] = currentNote
        } else {
            notes.insert(currentNote, at: 0)
        }

        notes.sort { $0.updatedAt > $1.updatedAt }
        saveNotes()
    }

    func newNote() {
        saveCurrentNote()
        currentNote = Note()
    }

    func loadNote(_ note: Note) {
        saveCurrentNote()
        currentNote = note
    }

    func deleteNote(_ note: Note) {
        notes.removeAll { $0.id == note.id }
        if currentNote.id == note.id {
            currentNote = Note()
        }
        saveNotes()
    }

    func searchNotes(query: String) -> [Note] {
        guard !query.isEmpty else { return notes }
        let lowered = query.lowercased()
        return notes.filter {
            $0.title.lowercased().contains(lowered) ||
            $0.content.lowercased().contains(lowered)
        }
    }
}
