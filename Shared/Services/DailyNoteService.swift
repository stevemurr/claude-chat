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
    private var syncOperationInProgress = false

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
        guard !isSyncing, !syncOperationInProgress else { return }

        isSyncing = true
        syncOperationInProgress = true
        syncError = nil

        // Flush currentNote into notesByDate before syncing to prevent data loss
        if currentNote.hasContent || !currentNote.chatMessages.isEmpty {
            notesByDate[currentNote.dateKey] = currentNote
        }

        // Snapshot the current note before the async call so we can detect
        // if the user edited it while we were awaiting the server.
        let preSyncNote = currentNote

        if let mergedNotes = await syncService.sync(localNotes: notesByDate) {
            notesByDate = mergedNotes

            // Check if the user edited currentNote while the sync was in flight
            let userEditedDuringSync = currentNote.updatedAt > preSyncNote.updatedAt

            if userEditedDuringSync {
                // User's local edit is newer — write it back into merged results
                notesByDate[currentNote.dateKey] = currentNote
            } else if let mergedVersion = mergedNotes[currentNote.dateKey] {
                if mergedVersion.updatedAt > currentNote.updatedAt {
                    // Server had a newer version — update currentNote
                    currentNote = mergedVersion
                    NotificationCenter.default.post(
                        name: .noteUpdated,
                        object: nil,
                        userInfo: ["dateKey": currentNote.dateKey]
                    )
                }
            }
            // If currentNote's dateKey is not in merged results, preserve it as-is

            saveNotesLocally()
        } else {
            syncError = syncService.syncError
        }

        syncOperationInProgress = false
        isSyncing = false
    }

    private func pushCurrentNoteToServer() {
        // Skip push if a sync is already in flight — the sync includes this note
        guard !syncOperationInProgress else { return }
        let noteToSend = currentNote
        Task {
            _ = await syncService.pushNote(noteToSend)
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

    /// Process a Claude response for note updates. Returns cleaned text and applied updates with operation info.
    func processResponseWithNoteUpdates(_ text: String) -> (cleanedText: String, toolUpdates: [(dateKey: String, operation: String, content: String, error: String?)]) {
        let (updates, cleanedText) = NoteUpdateParser.parse(text)
        var toolUpdates: [(dateKey: String, operation: String, content: String, error: String?)] = []

        for update in updates {
            let existingContent = notesByDate[update.dateKey]?.content ?? ""

            let result = NoteUpdateExecutor.apply(
                existingContent: existingContent,
                operation: update.operation,
                content: update.content,
                match: update.match
            )

            if let error = result.error {
                let errorMessage: String
                switch error {
                case .matchNotFound(let match):
                    errorMessage = "Could not find '\(match)' in the note."
                case .emptyMatch:
                    errorMessage = "Missing match attribute for \(update.operation.rawValue) operation."
                }
                toolUpdates.append((dateKey: update.dateKey, operation: update.operation.rawValue, content: existingContent, error: errorMessage))
                continue
            }

            if var existingNote = notesByDate[update.dateKey] {
                existingNote.content = result.content
                existingNote.updatedAt = Date()
                notesByDate[update.dateKey] = existingNote

                if currentNote.dateKey == update.dateKey {
                    currentNote.content = result.content
                    currentNote.updatedAt = Date()
                }
            } else {
                let newNote = DailyNote(dateKey: update.dateKey, content: result.content)
                notesByDate[update.dateKey] = newNote
            }

            NotificationCenter.default.post(
                name: .noteUpdated,
                object: nil,
                userInfo: ["dateKey": update.dateKey]
            )

            toolUpdates.append((dateKey: update.dateKey, operation: update.operation.rawValue, content: result.content, error: nil))
        }

        if !updates.isEmpty {
            saveNotes()
        }

        return (cleanedText, toolUpdates)
    }
}
