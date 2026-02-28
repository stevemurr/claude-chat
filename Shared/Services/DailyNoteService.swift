import Foundation
import os

@MainActor
class DailyNoteService: ObservableObject {
    private static let logger = Logger(subsystem: "com.claude.ClaudeChat", category: "DailyNoteService")

    @Published var notesByDate: [String: DailyNote] = [:]
    @Published var selectedDate: Date = Date()
    @Published var currentNote: DailyNote
    @Published var isSyncing = false
    @Published var syncError: String?
    @Published var lastError: String?

    private let savePath: URL
    private let syncService = SyncService()
    private var syncTimer: Timer?

    init() {
        // Use local storage
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("ClaudeChat", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.savePath = appDir.appendingPathComponent("daily_notes.json")
        self.currentNote = DailyNote(date: Date())

        loadNotes()
        selectDate(Date())

        // Start sync on launch
        Task {
            await performSync()
        }

        // Start periodic sync (every 30 seconds)
        startPeriodicSync()
    }

    deinit {
        syncTimer?.invalidate()
    }

    // MARK: - Sync

    private func startPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performSync()
            }
        }
    }

    func performSync() async {
        guard !isSyncing else { return }

        isSyncing = true
        syncError = nil

        // Flush currentNote into notesByDate before syncing to prevent data loss
        if currentNote.hasContent || !currentNote.chatMessages.isEmpty {
            notesByDate[currentNote.dateKey] = currentNote
        }

        if let mergedNotes = await syncService.sync(localNotes: notesByDate) {
            notesByDate = mergedNotes

            // Re-read current note from merged results
            if let updatedCurrentNote = mergedNotes[currentNote.dateKey] {
                if updatedCurrentNote.updatedAt > currentNote.updatedAt {
                    currentNote = updatedCurrentNote
                    NotificationCenter.default.post(
                        name: .noteUpdated,
                        object: nil,
                        userInfo: ["dateKey": currentNote.dateKey]
                    )
                }
            }

            saveNotesLocally()
        } else {
            syncError = syncService.syncError
        }

        isSyncing = false
    }

    private func pushCurrentNoteToServer() {
        Task {
            _ = await syncService.pushNote(currentNote)
        }
    }

    // MARK: - Date Selection

    func selectDate(_ date: Date) {
        selectedDate = date
        let key = DailyNote.keyFromDate(date)

        if let existing = notesByDate[key] {
            currentNote = existing
        } else {
            // Auto-create note for this date and add to notesByDate
            let newNote = DailyNote(date: date)
            currentNote = newNote
            notesByDate[key] = newNote
        }
    }

    // MARK: - Persistence

    func loadNotes() {
        guard FileManager.default.fileExists(atPath: savePath.path) else { return }

        do {
            let data = try Data(contentsOf: savePath)
            let notes = try JSONDecoder().decode([DailyNote].self, from: data)
            notesByDate = Dictionary(uniqueKeysWithValues: notes.map { ($0.dateKey, $0) })
        } catch {
            Self.logger.error("Failed to load notes: \(error.localizedDescription)")
            lastError = "Failed to load notes: \(error.localizedDescription)"
        }
    }

    private func saveNotesLocally() {
        let notesToSave = notesByDate.values.filter { $0.hasContent || !$0.chatMessages.isEmpty }
        let path = savePath

        // Encode on main thread (fast), write on background thread (potentially slow)
        do {
            let data = try JSONEncoder().encode(Array(notesToSave))
            Task.detached(priority: .utility) {
                do {
                    try data.write(to: path, options: .atomic)
                } catch {
                    Self.logger.error("Failed to write notes to disk: \(error.localizedDescription)")
                    await MainActor.run { [weak self] in
                        self?.lastError = "Failed to save notes: \(error.localizedDescription)"
                    }
                }
            }
        } catch {
            Self.logger.error("Failed to encode notes: \(error.localizedDescription)")
            lastError = "Failed to encode notes: \(error.localizedDescription)"
        }
    }

    func saveNotes() {
        saveNotesLocally()
    }

    func saveCurrentNote() {
        currentNote.updatedAt = Date()

        if currentNote.hasContent || !currentNote.chatMessages.isEmpty {
            notesByDate[currentNote.dateKey] = currentNote
        } else {
            // Remove empty notes
            notesByDate.removeValue(forKey: currentNote.dateKey)
        }

        saveNotesLocally()

        // Push to server
        pushCurrentNoteToServer()
    }

    // MARK: - Query Methods

    func hasContent(for date: Date) -> Bool {
        let key = DailyNote.keyFromDate(date)
        return notesByDate[key]?.hasContent ?? false
    }

    func note(for date: Date) -> DailyNote? {
        let key = DailyNote.keyFromDate(date)
        return notesByDate[key]
    }

    /// Search notes by content
    func searchNotes(query: String) -> [DailyNote] {
        guard !query.isEmpty else {
            // Return recent notes sorted by date
            return notesByDate.values
                .filter { $0.hasContent }
                .sorted { $0.dateKey > $1.dateKey }
        }

        let lowered = query.lowercased()
        return notesByDate.values
            .filter { $0.hasContent && $0.content.lowercased().contains(lowered) }
            .sorted { $0.dateKey > $1.dateKey }
    }

    /// Get all notes with content, sorted by date descending
    var allNotes: [DailyNote] {
        notesByDate.values
            .filter { $0.hasContent }
            .sorted { $0.dateKey > $1.dateKey }
    }

    /// Clear chat history for the current note
    func clearCurrentNoteChat() {
        currentNote.chatMessages = []
        currentNote.conversationStarted = false
        saveCurrentNote()
    }

    /// Add a chat message to the current note
    func addChatMessage(role: MessageRole, content: String) {
        let message = ChatMessage(role: role, content: content)
        currentNote.chatMessages.append(message)
    }

    /// Add a tool result message to the current note (for collapsible display)
    func addToolResultMessage(toolName: String, output: String) {
        let message = ChatMessage(
            role: .assistant,
            content: toolName,
            toolName: toolName,
            toolOutput: output
        )
        currentNote.chatMessages.append(message)
    }

    // MARK: - Note Update Processing

    /// Process a Claude response for note updates. Returns cleaned text and applied updates.
    func processResponseWithNoteUpdates(_ text: String) -> (cleanedText: String, toolUpdates: [(dateKey: String, content: String)]) {
        let (updates, cleanedText) = NoteUpdateParser.parse(text)
        var toolUpdates: [(dateKey: String, content: String)] = []

        for update in updates {
            if var existingNote = notesByDate[update.dateKey] {
                existingNote.content = update.content
                existingNote.updatedAt = Date()
                notesByDate[update.dateKey] = existingNote

                if currentNote.dateKey == update.dateKey {
                    currentNote.content = update.content
                    currentNote.updatedAt = Date()
                }
            } else {
                let newNote = DailyNote(dateKey: update.dateKey, content: update.content)
                notesByDate[update.dateKey] = newNote
            }

            NotificationCenter.default.post(
                name: .noteUpdated,
                object: nil,
                userInfo: ["dateKey": update.dateKey]
            )

            toolUpdates.append((dateKey: update.dateKey, content: update.content))
        }

        if !updates.isEmpty {
            saveNotes()
        }

        return (cleanedText, toolUpdates)
    }
}
