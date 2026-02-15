import SwiftUI
import MarkdownUI

struct ContentView: View {
    @StateObject private var claudeCLIService = ClaudeService()
    @StateObject private var claudeAPIService = ClaudeAPIService()
    @StateObject private var dailyNoteService = DailyNoteService()
    @StateObject private var commandPaletteService = CommandPaletteService()
    @ObservedObject private var settings = SettingsManager.shared

    /// Active Claude service based on user settings
    private var isLoading: Bool {
        settings.useAPIService ? claudeAPIService.isLoading : claudeCLIService.isLoading
    }


    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showChatSidebar: Bool = true
    @State private var inputText = ""
    @State private var streamingText = ""
    @State private var isWorking = false
    @State private var showSettings = false
    @State private var showAutocomplete = false
    @State private var autocompleteQuery = ""
    @State private var autocompleteSelectedIndex = 0
    @State private var isAtBottom = true
    @State private var showScrollButton = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        mainContent(noteService: dailyNoteService)
            .onAppear {
                commandPaletteService.configure(dailyNoteService: dailyNoteService, historyService: nil)
                isInputFocused = true
            }
    }

    @ViewBuilder
    private func mainContent(noteService: DailyNoteService) -> some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Left: Calendar sidebar
            calendarSidebar(noteService: noteService)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            // Center: Editor
            noteEditorColumn(noteService: noteService)
                .frame(minWidth: 300)
                .inspector(isPresented: $showChatSidebar) {
                    // Right: Chat inspector
                    chatSidebarColumn(noteService: noteService)
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
                }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onReceive(NotificationCenter.default.publisher(for: .focusInput)) { _ in
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChat)) { _ in
            noteService.clearCurrentNoteChat()
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newNote)) { _ in
            noteService.selectDate(Date())
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleCalendarSidebar)) { _ in
            withAnimation {
                if columnVisibility == .detailOnly {
                    columnVisibility = .all
                } else {
                    columnVisibility = .detailOnly
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleChatSidebar)) { _ in
            withAnimation {
                showChatSidebar.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCommandPalette)) { _ in
            showAutocomplete = false
            commandPaletteService.show()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .overlay {
            if commandPaletteService.isVisible {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.25)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .onTapGesture {
                            commandPaletteService.dismiss()
                        }

                    CommandPaletteView(
                        service: commandPaletteService,
                        onSelect: { item in
                            handleCommandPaletteSelection(item, noteService: noteService)
                        }
                    )
                    .padding(.top, 60)
                }
            }
        }
    }

    // MARK: - Calendar Sidebar

    private func calendarSidebar(noteService: DailyNoteService) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("Daily Notes")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(12)

            Divider()

            CalendarView(dailyNoteService: noteService)
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }

    // MARK: - Note Editor Column

    private var isCalendarVisible: Bool {
        columnVisibility != .detailOnly
    }

    private func noteEditorColumn(noteService: DailyNoteService) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: {
                    withAnimation {
                        if columnVisibility == .detailOnly {
                            columnVisibility = .all
                        } else {
                            columnVisibility = .detailOnly
                        }
                    }
                }) {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 14))
                        .foregroundColor(isCalendarVisible ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle Calendar (\u{2318}\u{2303}S)")

                Spacer()

                Text(noteService.currentNote.displayTitle)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")

                Button(action: {
                    withAnimation {
                        showChatSidebar.toggle()
                    }
                }) {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: 14))
                        .foregroundColor(showChatSidebar ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle Chat (\u{2318}\u{21E7}L)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            NotepadContentView(dailyNoteService: noteService)
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - Chat Sidebar Column

    private func chatSidebarColumn(noteService: DailyNoteService) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label("Chat", systemImage: "bubble.left.fill")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()

                if !noteService.currentNote.chatMessages.isEmpty {
                    Button(action: {
                        noteService.clearCurrentNoteChat()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear Chat")
                }
            }
            .padding(12)

            Divider()

            chatMessagesList(noteService: noteService)

            Divider()

            chatInputArea(noteService: noteService)
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }

    // MARK: - Chat Messages List

    private func chatMessagesList(noteService: DailyNoteService) -> some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(noteService.currentNote.chatMessages) { message in
                            ChatMessageBlock(message: message)
                                .id(message.id)
                        }

                        if isLoading {
                            StreamingBlock(text: streamingText, isWorking: isWorking)
                                .id("streaming")
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(12)
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geometry.frame(in: .named("chatScroll")).maxY
                                )
                        }
                    )
                }
                .coordinateSpace(name: "chatScroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                    let newIsAtBottom = maxY < 100
                    if newIsAtBottom != isAtBottom {
                        isAtBottom = newIsAtBottom
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showScrollButton = !newIsAtBottom
                        }
                    }
                }
                .onChange(of: noteService.currentNote.chatMessages.count) { _, _ in
                    if isAtBottom {
                        scrollToBottom(proxy: proxy)
                    }
                }
                .onChange(of: claudeCLIService.isLoading) { _, _ in
                    if isAtBottom {
                        scrollToBottom(proxy: proxy)
                    }
                }
                .onChange(of: claudeAPIService.isLoading) { _, _ in
                    if isAtBottom {
                        scrollToBottom(proxy: proxy)
                    }
                }
                .onChange(of: streamingText) { _, _ in
                    if isAtBottom {
                        scrollToBottom(proxy: proxy)
                    }
                }
                .background(
                    ScrollProxyHolder(proxy: proxy, trigger: $showScrollButton)
                )
            }

            if showScrollButton {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showScrollButton = false
                        isAtBottom = true
                    }
                }) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
    }

    // MARK: - Chat Input Area

    private func chatInputArea(noteService: DailyNoteService) -> some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if showAutocomplete {
                    NoteAutocompletePopup(
                        dailyNoteService: noteService,
                        query: autocompleteQuery,
                        selectedIndex: $autocompleteSelectedIndex,
                        onSelect: { note in
                            insertNoteReference(note)
                        },
                        onDismiss: {
                            showAutocomplete = false
                        }
                    )
                }

                InputArea(
                    inputText: $inputText,
                    isInputFocused: _isInputFocused,
                    isLoading: isLoading,
                    onSend: { sendChatMessage(noteService: noteService) },
                    onTab: { selectCurrentAutocomplete(noteService: noteService) },
                    onArrowUp: { moveAutocompleteSelection(by: -1, noteService: noteService) },
                    onArrowDown: { moveAutocompleteSelection(by: 1, noteService: noteService) },
                    onEscape: { showAutocomplete = false },
                    shouldInterceptKeys: { showAutocomplete }
                )
            }
        }
        .onChange(of: inputText) { _, newValue in
            updateAutocomplete(text: newValue, noteService: noteService)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    // MARK: - Command Palette

    private func handleCommandPaletteSelection(_ item: CommandPaletteItem, noteService: DailyNoteService) {
        commandPaletteService.dismiss()

        switch item.type {
        case .action:
            switch item.action {
            case .newChat:
                noteService.clearCurrentNoteChat()
                isInputFocused = true
            case .newNote:
                noteService.selectDate(Date())
            case .none:
                break
            }
        case .dailyNote:
            if let dailyNote = item.dailyNote,
               let date = DailyNote.dateFromKey(dailyNote.dateKey) {
                noteService.selectDate(date)
            }
        case .chat:
            break
        }
    }

    // MARK: - Autocomplete

    private func updateAutocomplete(text: String, noteService: DailyNoteService) {
        guard let atRange = findActiveAtSymbol(in: text) else {
            showAutocomplete = false
            autocompleteQuery = ""
            return
        }

        let query = String(text[atRange])
        autocompleteQuery = query
        autocompleteSelectedIndex = 0

        let results = noteService.searchNotes(query: query)
        showAutocomplete = !results.isEmpty
    }

    private func findActiveAtSymbol(in text: String) -> Range<String.Index>? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }

        let afterAt = text[text.index(after: atIndex)...]

        if afterAt.hasPrefix("\"") {
            let afterQuote = afterAt.dropFirst()
            if afterQuote.contains("\"") {
                return nil
            }
            let queryStart = text.index(atIndex, offsetBy: 2)
            if queryStart < text.endIndex {
                return queryStart..<text.endIndex
            }
            return nil
        }

        let queryStart = text.index(after: atIndex)
        if queryStart <= text.endIndex && queryStart != text.endIndex {
            let queryText = text[queryStart...]
            if queryText.isEmpty { return nil }
            return queryStart..<text.endIndex
        }

        return nil
    }

    private func insertNoteReference(_ note: DailyNote) {
        if let atIndex = inputText.lastIndex(of: "@") {
            let before = inputText[..<atIndex]
            inputText = before + "@\"\(note.displayTitle)\" "
        }
        showAutocomplete = false
    }

    private func autocompleteResults(noteService: DailyNoteService) -> [DailyNote] {
        Array(noteService.searchNotes(query: autocompleteQuery).prefix(5))
    }

    private func moveAutocompleteSelection(by delta: Int, noteService: DailyNoteService) {
        let results = autocompleteResults(noteService: noteService)
        guard !results.isEmpty else { return }
        autocompleteSelectedIndex = (autocompleteSelectedIndex + delta + results.count) % results.count
    }

    private func selectCurrentAutocomplete(noteService: DailyNoteService) {
        let results = autocompleteResults(noteService: noteService)
        guard autocompleteSelectedIndex < results.count else { return }
        insertNoteReference(results[autocompleteSelectedIndex])
    }

    // MARK: - Note Context Extraction

    private func extractNoteContext(from text: String, noteService: DailyNoteService) -> String? {
        let pattern = #"@"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var contextParts: [String] = []

        for match in matches {
            if let titleRange = Range(match.range(at: 1), in: text) {
                let title = String(text[titleRange])
                if let note = noteService.allNotes.first(where: { $0.displayTitle == title }) {
                    contextParts.append("--- Note: \(note.displayTitle) (date: \(note.dateKey)) ---\n\(note.content)")
                }
            }
        }

        return contextParts.isEmpty ? nil : contextParts.joined(separator: "\n\n")
    }

    private func processResponseWithNoteUpdates(_ text: String, noteService: DailyNoteService) -> (cleanedText: String, toolUpdates: [(dateKey: String, content: String)]) {
        let (updates, cleanedText) = NoteUpdateParser.parse(text)
        var toolUpdates: [(dateKey: String, content: String)] = []

        for update in updates {
            if var existingNote = noteService.notesByDate[update.dateKey] {
                existingNote.content = update.content
                existingNote.updatedAt = Date()
                noteService.notesByDate[update.dateKey] = existingNote

                if noteService.currentNote.dateKey == update.dateKey {
                    noteService.currentNote.content = update.content
                    noteService.currentNote.updatedAt = Date()
                }
            } else {
                let newNote = DailyNote(dateKey: update.dateKey, content: update.content)
                noteService.notesByDate[update.dateKey] = newNote
            }

            NotificationCenter.default.post(
                name: .noteUpdated,
                object: nil,
                userInfo: ["dateKey": update.dateKey]
            )

            toolUpdates.append((dateKey: update.dateKey, content: update.content))
        }

        if !updates.isEmpty {
            noteService.saveNotes()
        }

        return (cleanedText, toolUpdates)
    }

    // MARK: - Send Message

    private func sendChatMessage(noteService: DailyNoteService) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let currentNote = noteService.currentNote
        var contextParts: [String] = []

        // Add yesterday's note if it exists
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: noteService.selectedDate),
           let yesterdayNote = noteService.note(for: yesterday),
           yesterdayNote.hasContent {
            contextParts.append("""
                --- Yesterday's Note: \(yesterdayNote.displayTitle) (date: \(yesterdayNote.dateKey)) ---
                \(yesterdayNote.content)
                """)
        }

        // Add current note
        contextParts.append("""
            --- Current Note: \(currentNote.displayTitle) (date: \(currentNote.dateKey)) ---
            \(currentNote.content)
            """)

        // Add tomorrow's note if it exists
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: noteService.selectedDate),
           let tomorrowNote = noteService.note(for: tomorrow),
           tomorrowNote.hasContent {
            contextParts.append("""
                --- Tomorrow's Note: \(tomorrowNote.displayTitle) (date: \(tomorrowNote.dateKey)) ---
                \(tomorrowNote.content)
                """)
        }

        if let additionalContext = extractNoteContext(from: text, noteService: noteService) {
            contextParts.append(additionalContext)
        }

        let noteContext = contextParts.joined(separator: "\n\n")

        noteService.addChatMessage(role: .user, content: text)

        let shouldContinue = currentNote.conversationStarted
        inputText = ""
        streamingText = ""
        isWorking = false
        showAutocomplete = false

        Task {
            var addedMessages = Set<String>()

            let responses: [String]?
            let lastError: String?

            if settings.useAPIService {
                responses = await claudeAPIService.sendMessage(
                    text,
                    noteContext: noteContext,
                    continueConversation: shouldContinue
                ) { update in
                    streamingText = update.text
                    isWorking = update.isWorking

                    if update.isComplete && !update.text.isEmpty && !addedMessages.contains(update.text) {
                        addedMessages.insert(update.text)
                        let (cleanedText, toolUpdates) = processResponseWithNoteUpdates(update.text, noteService: noteService)

                        // Add tool result messages for each note update
                        for toolUpdate in toolUpdates {
                            noteService.addToolResultMessage(
                                toolName: "note_update",
                                output: "Updated note \(toolUpdate.dateKey):\n\n\(toolUpdate.content)"
                            )
                        }

                        if !cleanedText.isEmpty {
                            noteService.addChatMessage(role: .assistant, content: cleanedText)
                        }
                        streamingText = ""
                    }
                }
                lastError = claudeAPIService.lastError
            } else {
                responses = await claudeCLIService.sendMessage(
                    text,
                    noteContext: noteContext,
                    continueConversation: shouldContinue
                ) { update in
                    streamingText = update.text
                    isWorking = update.isWorking

                    if update.isComplete && !update.text.isEmpty && !addedMessages.contains(update.text) {
                        addedMessages.insert(update.text)
                        let (cleanedText, toolUpdates) = processResponseWithNoteUpdates(update.text, noteService: noteService)

                        // Add tool result messages for each note update
                        for toolUpdate in toolUpdates {
                            noteService.addToolResultMessage(
                                toolName: "note_update",
                                output: "Updated note \(toolUpdate.dateKey):\n\n\(toolUpdate.content)"
                            )
                        }

                        if !cleanedText.isEmpty {
                            noteService.addChatMessage(role: .assistant, content: cleanedText)
                        }
                        streamingText = ""
                    }
                }
                lastError = claudeCLIService.lastError
            }

            noteService.currentNote.conversationStarted = true

            if let responses = responses {
                for response in responses {
                    if !response.isEmpty && !addedMessages.contains(response) {
                        let (cleanedText, toolUpdates) = processResponseWithNoteUpdates(response, noteService: noteService)

                        // Add tool result messages for each note update
                        for toolUpdate in toolUpdates {
                            noteService.addToolResultMessage(
                                toolName: "note_update",
                                output: "Updated note \(toolUpdate.dateKey):\n\n\(toolUpdate.content)"
                            )
                        }

                        if !cleanedText.isEmpty {
                            noteService.addChatMessage(role: .assistant, content: cleanedText)
                        }
                    }
                }
            } else if let error = lastError {
                noteService.addChatMessage(role: .assistant, content: "Error: \(error)")
            }

            streamingText = ""
            isWorking = false

            noteService.saveCurrentNote()
        }
    }
}

// MARK: - Chat Message Block (compact for sidebar)

struct ChatMessageBlock: View {
    let message: ChatMessage

    @State private var copied = false

    var body: some View {
        // Check if this is a tool result message
        if message.isToolResult, let toolName = message.toolName, let toolOutput = message.toolOutput {
            ToolResultBlock(toolName: toolName, output: toolOutput)
        } else {
            regularMessageView
        }
    }

    private var regularMessageView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(
                    message.role == .user ? "You" : "Claude",
                    systemImage: message.role == .user ? "person.fill" : "sparkles"
                )
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)

                Spacer()

                Button(action: copyToClipboard) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundColor(copied ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            Markdown(message.content)
                .textSelection(.enabled)
                .markdownTheme(.chatSidebar)
                .font(.system(size: 12))
        }
        .padding(10)
        .background(backgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }

    private var backgroundColor: Color {
        message.role == .user
            ? Color.accentColor.opacity(0.1)
            : Color(NSColor.controlBackgroundColor)
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        copied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

// MARK: - Tool Result Block (collapsible)

struct ToolResultBlock: View {
    let toolName: String
    let output: String
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - always visible
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)

                    Text(toolName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                Divider()
                    .padding(.horizontal, 10)

                Markdown(output)
                    .textSelection(.enabled)
                    .markdownTheme(.chatSidebar)
                    .font(.system(size: 11))
                    .padding(10)
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Streaming Block

struct StreamingBlock: View {
    let text: String
    let isWorking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Claude", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()

                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text(isWorking ? "Working..." : "Streaming")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            if text.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text(isWorking ? "Running tools..." : "Thinking...")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Markdown(text)
                    .textSelection(.enabled)
                    .markdownTheme(.chatSidebar)
                    .font(.system(size: 12))
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Input Area

struct InputArea: View {
    @Binding var inputText: String
    @FocusState var isInputFocused: Bool
    let isLoading: Bool
    let onSend: () -> Void
    var onTab: () -> Void = {}
    var onArrowUp: () -> Void = {}
    var onArrowDown: () -> Void = {}
    var onEscape: () -> Void = {}
    var shouldInterceptKeys: () -> Bool = { false }

    @State private var textHeight: CGFloat = 22

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(alignment: .bottom, spacing: 6) {
                ChatInputField(
                    text: $inputText,
                    placeholder: "Ask Claude...",
                    textHeight: $textHeight,
                    onSubmit: onSend,
                    onTab: onTab,
                    onArrowUp: onArrowUp,
                    onArrowDown: onArrowDown,
                    onEscape: onEscape,
                    shouldInterceptKeys: shouldInterceptKeys
                )
                .frame(height: min(max(textHeight, 22), 100))

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(inputText.isEmpty || isLoading ? .secondary.opacity(0.4) : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || isLoading)
                .padding(.bottom, 1)
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Markdown Theme for Chat Sidebar

extension MarkdownUI.Theme {
    static let chatSidebar = Theme()
        .text {
            FontSize(12)
            ForegroundColor(.primary)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(11)
            BackgroundColor(Color(NSColor.controlBackgroundColor))
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .fontDesign(.monospaced)
                    .font(.system(size: 11))
                    .padding(10)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
            )
        }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: 12, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(16)
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: 10, bottom: 4)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(14)
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 8, bottom: 4)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(13)
                }
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 4)
        }
        .paragraph { configuration in
            configuration.label
                .markdownMargin(top: 0, bottom: 8)
        }
}

// MARK: - Scroll Helpers

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ScrollProxyHolder: View {
    let proxy: ScrollViewProxy
    @Binding var trigger: Bool

    var body: some View {
        Color.clear
            .onChange(of: trigger) { _, newValue in
                if !newValue {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
    }
}

// MARK: - ChatInputField (NSViewRepresentable with NSTextView for multiline support)

struct ChatInputField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Binding var textHeight: CGFloat
    var onSubmit: () -> Void
    var onTab: () -> Void
    var onArrowUp: () -> Void
    var onArrowDown: () -> Void
    var onEscape: () -> Void
    var shouldInterceptKeys: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = ChatTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.allowsUndo = true

        textView.onSubmit = { context.coordinator.parent.onSubmit() }
        textView.onTabKey = { context.coordinator.handleTab() }
        textView.onArrowUpKey = { context.coordinator.handleArrowUp() }
        textView.onArrowDownKey = { context.coordinator.handleArrowDown() }
        textView.onEscapeKey = { context.coordinator.handleEscape() }
        textView.shouldInterceptKeys = { context.coordinator.parent.shouldInterceptKeys() }
        textView.onHeightChange = { height in
            DispatchQueue.main.async {
                context.coordinator.parent.textHeight = height
            }
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView

        DispatchQueue.main.async {
            context.coordinator.updateHeight()
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != text {
            textView.string = text
            context.coordinator.updateHeight()
        }

        if let chatTextView = textView as? ChatTextView {
            chatTextView.placeholderString = placeholder
            chatTextView.needsDisplay = true
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChatInputField
        weak var textView: NSTextView?

        init(_ parent: ChatInputField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateHeight()
        }

        func updateHeight() {
            guard let textView = textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let newHeight = usedRect.height + textView.textContainerInset.height * 2

            if abs(newHeight - parent.textHeight) > 1 {
                DispatchQueue.main.async {
                    self.parent.textHeight = newHeight
                }
            }
        }

        func handleTab() -> Bool {
            guard parent.shouldInterceptKeys() else { return false }
            parent.onTab()
            return true
        }

        func handleArrowUp() -> Bool {
            guard parent.shouldInterceptKeys() else { return false }
            parent.onArrowUp()
            return true
        }

        func handleArrowDown() -> Bool {
            guard parent.shouldInterceptKeys() else { return false }
            parent.onArrowDown()
            return true
        }

        func handleEscape() -> Bool {
            guard parent.shouldInterceptKeys() else { return false }
            parent.onEscape()
            return true
        }
    }
}

// Custom NSTextView that handles Return vs Shift+Return
class ChatTextView: NSTextView {
    var placeholderString: String = ""
    var onSubmit: (() -> Void)?
    var onTabKey: (() -> Bool)?
    var onArrowUpKey: (() -> Bool)?
    var onArrowDownKey: (() -> Bool)?
    var onEscapeKey: (() -> Bool)?
    var shouldInterceptKeys: (() -> Bool)?
    var onHeightChange: ((CGFloat) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if string.isEmpty && !placeholderString.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: font ?? NSFont.systemFont(ofSize: 13)
            ]
            let inset = textContainerInset
            let rect = NSRect(x: inset.width, y: inset.height, width: bounds.width - inset.width * 2, height: bounds.height - inset.height * 2)
            placeholderString.draw(in: rect, withAttributes: attrs)
        }
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags

        if keyCode == 36 {
            if modifiers.contains(.shift) {
                insertNewline(nil)
            } else {
                onSubmit?()
            }
            return
        }

        if keyCode == 48 {
            if onTabKey?() == true {
                return
            }
        }

        if keyCode == 126 {
            if onArrowUpKey?() == true {
                return
            }
        }

        if keyCode == 125 {
            if onArrowDownKey?() == true {
                return
            }
        }

        if keyCode == 53 {
            if onEscapeKey?() == true {
                return
            }
        }

        super.keyDown(with: event)
    }
}

#Preview {
    ContentView()
}
