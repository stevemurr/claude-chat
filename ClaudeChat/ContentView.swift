import SwiftUI
import MarkdownUI

enum AppMode: Hashable {
    case chat
    case notepad
}

struct ContentView: View {
    @StateObject private var claudeService = ClaudeService()
    @StateObject private var historyService = ChatHistoryService()
    @StateObject private var noteService = NoteService()
    @StateObject private var commandPaletteService = CommandPaletteService()
    @StateObject private var titleService = TitleService()
    @State private var inputText = ""
    @State private var showSettings = false
    @State private var streamingText = ""
    @State private var isWorking = false
    @State private var isAtBottom = true
    @State private var showScrollButton = false
    @State private var appMode: AppMode = .chat
    @State private var showAutocomplete = false
    @State private var autocompleteQuery = ""
    @State private var autocompleteSelectedIndex = 0
    @State private var columnVisibility: NavigationSplitViewVisibility = .automatic
    @State private var selectedSessionID: UUID?
    @State private var selectedNoteID: UUID?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            detailContent
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            isInputFocused = true
            commandPaletteService.configure(noteService: noteService, historyService: historyService)
            // Sync initial selection
            selectedSessionID = historyService.currentSession.id
            selectedNoteID = noteService.currentNote.id
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusInput)) { _ in
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChat)) { _ in
            if appMode == .chat {
                historyService.newSession()
                claudeService.resetConversation()
                selectedSessionID = historyService.currentSession.id
                isInputFocused = true
            } else {
                noteService.newNote()
                selectedNoteID = noteService.currentNote.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newNote)) { _ in
            appMode = .notepad
            noteService.newNote()
            selectedNoteID = noteService.currentNote.id
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMode)) { _ in
            cycleMode()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCommandPalette)) { _ in
            showAutocomplete = false
            commandPaletteService.show()
        }
        .onChange(of: appMode) { newMode in
            if newMode == .chat {
                // Save any in-progress note when switching to chat
                noteService.saveCurrentNote()
            }
        }
        .onChange(of: selectedSessionID) { newID in
            guard let newID = newID else { return }
            if newID != historyService.currentSession.id {
                if let session = historyService.sessions.first(where: { $0.id == newID }) {
                    historyService.loadSession(session)
                    claudeService.resetConversation()
                }
            }
        }
        .onChange(of: selectedNoteID) { newID in
            guard let newID = newID else { return }
            if newID != noteService.currentNote.id {
                if let note = noteService.notes.first(where: { $0.id == newID }) {
                    noteService.loadNote(note)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .overlay {
            if commandPaletteService.isVisible {
                ZStack(alignment: .top) {
                    // Backdrop
                    Color.black.opacity(0.25)
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .onTapGesture {
                            commandPaletteService.dismiss()
                        }

                    // Palette positioned near top
                    CommandPaletteView(
                        service: commandPaletteService,
                        onSelect: { item in
                            handleCommandPaletteSelection(item)
                        }
                    )
                    .padding(.top, 60)
                }
            }
        }
    }

    // MARK: - Sidebar Content

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Mode switcher in sidebar header
            sidebarHeader

            Divider()

            // Sidebar list based on mode
            switch appMode {
            case .chat:
                chatSidebarList
            case .notepad:
                noteSidebarList
            }
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
    }

    private var sidebarHeader: some View {
        VStack(spacing: 12) {
            // Mode Picker
            Picker("Mode", selection: $appMode) {
                Label("Chat", systemImage: "bubble.left.fill")
                    .tag(AppMode.chat)
                Label("Notes", systemImage: "doc.text")
                    .tag(AppMode.notepad)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            // New button
            Button(action: {
                switch appMode {
                case .chat:
                    historyService.newSession()
                    claudeService.resetConversation()
                    selectedSessionID = historyService.currentSession.id
                    isInputFocused = true
                case .notepad:
                    noteService.newNote()
                    selectedNoteID = noteService.currentNote.id
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text(appMode == .chat ? "New Chat" : "New Note")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private var chatSidebarList: some View {
        List(selection: $selectedSessionID) {
            ForEach(historyService.sessions) { session in
                SessionRowView(session: session, isSelected: session.id == selectedSessionID)
                    .tag(session.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            historyService.deleteSession(session)
                            if selectedSessionID == session.id {
                                selectedSessionID = historyService.currentSession.id
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
    }

    private var noteSidebarList: some View {
        List(selection: $selectedNoteID) {
            ForEach(noteService.notes) { note in
                NoteRowView(note: note, isSelected: note.id == selectedNoteID)
                    .tag(note.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            noteService.deleteNote(note)
                            if selectedNoteID == note.id {
                                selectedNoteID = noteService.currentNote.id
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        VStack(spacing: 0) {
            // Detail header with settings
            detailHeader

            Divider()

            // Content area - conditional based on mode
            switch appMode {
            case .chat:
                chatContent

            case .notepad:
                NotepadContentView(noteService: noteService, titleService: titleService)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            // Current item title
            Text(appMode == .chat ? historyService.currentSession.title : noteService.currentNote.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer()

            Button(action: { showSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Chat Content (extracted from body)

    private var chatContent: some View {
        VStack(spacing: 0) {
            // Messages
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(historyService.currentSession.messages) { message in
                                MessageBlock(message: message)
                                    .id(message.id)
                            }

                            if claudeService.isLoading {
                                StreamingBlock(text: streamingText, isWorking: isWorking)
                                    .id("streaming")
                            }

                            // Bottom anchor for scroll detection
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(20)
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(
                                        key: ScrollOffsetPreferenceKey.self,
                                        value: geometry.frame(in: .named("scroll")).maxY
                                    )
                            }
                        )
                    }
                    .coordinateSpace(name: "scroll")
                    .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                        let newIsAtBottom = maxY < 100
                        if newIsAtBottom != isAtBottom {
                            isAtBottom = newIsAtBottom
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showScrollButton = !newIsAtBottom
                            }
                        }
                    }
                    .onChange(of: historyService.currentSession.messages.count) { _ in
                        if isAtBottom {
                            scrollToBottom(proxy: proxy)
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showScrollButton = true
                            }
                        }
                    }
                    .onChange(of: claudeService.isLoading) { _ in
                        if isAtBottom {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onChange(of: streamingText) { _ in
                        if isAtBottom {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onChange(of: isWorking) { _ in
                        if isAtBottom {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .onChange(of: showScrollButton) { show in
                        if !show {
                            scrollToBottom(proxy: proxy)
                        }
                    }
                    .background(
                        ScrollProxyHolder(proxy: proxy, trigger: $showScrollButton)
                    )
                }

                // Scroll to bottom button
                if showScrollButton {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showScrollButton = false
                            isAtBottom = true
                        }
                    }) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }

            Divider()

            // Input area with autocomplete
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if showAutocomplete {
                        NoteAutocompletePopup(
                            noteService: noteService,
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
                        isLoading: claudeService.isLoading,
                        onSend: sendMessage,
                        onTab: { selectCurrentAutocomplete() },
                        onArrowUp: { moveAutocompleteSelection(by: -1) },
                        onArrowDown: { moveAutocompleteSelection(by: 1) },
                        onEscape: { showAutocomplete = false },
                        shouldInterceptKeys: { showAutocomplete }
                    )
                }
            }
            .onChange(of: inputText) { newValue in
                updateAutocomplete(text: newValue)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func handleCommandPaletteSelection(_ item: CommandPaletteItem) {
        commandPaletteService.dismiss()

        switch item.type {
        case .action:
            switch item.action {
            case .newChat:
                appMode = .chat
                historyService.newSession()
                claudeService.resetConversation()
                selectedSessionID = historyService.currentSession.id
                isInputFocused = true
            case .newNote:
                appMode = .notepad
                noteService.newNote()
                selectedNoteID = noteService.currentNote.id
            case .none:
                break
            }
        case .note:
            if let note = item.note {
                appMode = .notepad
                noteService.loadNote(note)
                selectedNoteID = note.id
            }
        case .chat:
            if let session = item.session {
                appMode = .chat
                historyService.loadSession(session)
                claudeService.resetConversation()
                selectedSessionID = session.id
                isInputFocused = true
            }
        }
    }

    private func cycleMode() {
        switch appMode {
        case .chat:
            appMode = .notepad
        case .notepad:
            noteService.saveCurrentNote()
            appMode = .chat
            isInputFocused = true
        }
    }

    // MARK: - Autocomplete

    private func updateAutocomplete(text: String) {
        // Find the last @ that might be starting a reference
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
        // Look for @ followed by non-whitespace chars that haven't been "closed" with a quote
        // Pattern: @sometext (not inside an existing @"..." reference)
        guard let atIndex = text.lastIndex(of: "@") else { return nil }

        let afterAt = text[text.index(after: atIndex)...]

        // If there's a closing quote already, this reference is complete
        if afterAt.hasPrefix("\"") {
            // Check if the quoted reference is closed
            let afterQuote = afterAt.dropFirst()
            if afterQuote.contains("\"") {
                return nil  // Closed reference
            }
            // Open quoted reference - use content after the quote as query
            let queryStart = text.index(atIndex, offsetBy: 2)
            if queryStart < text.endIndex {
                return queryStart..<text.endIndex
            }
            return nil
        }

        // Unquoted @ - use text after @ as query
        let queryStart = text.index(after: atIndex)
        if queryStart <= text.endIndex && queryStart != text.endIndex {
            // Don't show autocomplete if there's a space right after @
            let queryText = text[queryStart...]
            if queryText.isEmpty { return nil }
            return queryStart..<text.endIndex
        }

        return nil
    }

    private func insertNoteReference(_ note: Note) {
        // Find the @ symbol and replace everything from @ to cursor with @"Title"
        if let atIndex = inputText.lastIndex(of: "@") {
            let before = inputText[..<atIndex]
            inputText = before + "@\"\(note.title)\" "
        }
        showAutocomplete = false
    }

    private var autocompleteResults: [Note] {
        Array(noteService.searchNotes(query: autocompleteQuery).prefix(5))
    }

    private func moveAutocompleteSelection(by delta: Int) {
        let results = autocompleteResults
        guard !results.isEmpty else { return }
        autocompleteSelectedIndex = (autocompleteSelectedIndex + delta + results.count) % results.count
    }

    private func selectCurrentAutocomplete() {
        let results = autocompleteResults
        guard autocompleteSelectedIndex < results.count else { return }
        insertNoteReference(results[autocompleteSelectedIndex])
    }

    // MARK: - Note Context Extraction

    private func extractNoteContext(from text: String) -> String? {
        // Parse @"Title" references
        let pattern = #"@"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var contextParts: [String] = []

        for match in matches {
            if let titleRange = Range(match.range(at: 1), in: text) {
                let title = String(text[titleRange])
                // Find the note by title
                if let note = noteService.notes.first(where: { $0.title == title }) {
                    contextParts.append("--- Note: \(note.title) ---\n\(note.content)")
                }
            }
        }

        return contextParts.isEmpty ? nil : contextParts.joined(separator: "\n\n")
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Extract note context from @"Title" references
        let noteContext = extractNoteContext(from: text)

        let userMessage = ChatMessage(role: .user, content: text)
        historyService.addMessageToCurrentSession(userMessage)
        inputText = ""
        streamingText = ""
        isWorking = false
        showAutocomplete = false

        Task {
            var addedMessages = Set<String>()

            let responses = await claudeService.sendMessage(text, noteContext: noteContext) { update in
                streamingText = update.text
                isWorking = update.isWorking

                // If a message is complete, add it as a separate block
                if update.isComplete && !update.text.isEmpty && !addedMessages.contains(update.text) {
                    addedMessages.insert(update.text)
                    let assistantMessage = ChatMessage(role: .assistant, content: update.text)
                    historyService.addMessageToCurrentSession(assistantMessage)
                    streamingText = ""
                }
            }

            // Add any remaining messages that weren't added during streaming
            if let responses = responses {
                for response in responses {
                    if !response.isEmpty && !addedMessages.contains(response) {
                        let assistantMessage = ChatMessage(role: .assistant, content: response)
                        historyService.addMessageToCurrentSession(assistantMessage)
                    }
                }
            } else if let error = claudeService.lastError {
                let errorMessage = ChatMessage(role: .assistant, content: "Error: \(error)")
                historyService.addMessageToCurrentSession(errorMessage)
            }

            streamingText = ""
            isWorking = false

            // Generate AI title after first assistant response
            if !historyService.currentSession.titleGenerated {
                let messages = historyService.currentSession.messages
                if let firstUser = messages.first(where: { $0.role == .user }),
                   let firstAssistant = messages.first(where: { $0.role == .assistant }) {
                    let context = firstUser.content + "\n\n" + firstAssistant.content
                    Task {
                        if let title = await titleService.generateTitle(for: context) {
                            historyService.currentSession.title = title
                            historyService.currentSession.titleGenerated = true
                            historyService.saveCurrentSession()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Session Row View (for native List)

struct SessionRowView: View {
    let session: ChatSession
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .foregroundColor(.primary)

            Text(session.updatedAt.formatted(.relative(presentation: .named)))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Note Row View (for native List)

struct NoteRowView: View {
    let note: Note
    let isSelected: Bool

    var body: some View {
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
        .padding(.vertical, 2)
    }
}

// MARK: - Message Block

struct MessageBlock: View {
    let message: ChatMessage

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with role and toolbar
            HStack {
                Label(
                    message.role == .user ? "You" : "Claude",
                    systemImage: message.role == .user ? "person.fill" : "sparkles"
                )
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

                Spacer()

                MessageToolbar(content: message.content, copied: $copied)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(headerColor)

            // Content
            Markdown(message.content)
                .textSelection(.enabled)
                .markdownTheme(.custom)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
        }
        .background(backgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var backgroundColor: Color {
        Color(NSColor.controlBackgroundColor)
    }

    private var headerColor: Color {
        Color(NSColor.controlBackgroundColor).opacity(0.8)
    }

    private var borderColor: Color {
        Color(NSColor.separatorColor).opacity(0.5)
    }
}

struct MessageToolbar: View {
    let content: String
    @Binding var copied: Bool

    var body: some View {
        HStack(spacing: 8) {
            Button(action: copyToClipboard) {
                HStack(spacing: 4) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    if copied {
                        Text("Copied")
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(copied ? .green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        copied = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

// MARK: - Streaming Block

struct StreamingBlock: View {
    let text: String
    let isWorking: Bool

    @State private var dotCount = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Claude", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()

                // Status indicator
                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text(isWorking ? "Working..." : "Streaming")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8))

            if text.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(isWorking ? "Running tools..." : "Thinking...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            } else {
                Markdown(text)
                    .textSelection(.enabled)
                    .markdownTheme(.custom)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
        )
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 3
        }
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
        HStack(alignment: .bottom, spacing: 10) {
            HStack(alignment: .bottom, spacing: 8) {
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
                .frame(height: min(max(textHeight, 22), 150))

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(inputText.isEmpty || isLoading ? .secondary.opacity(0.4) : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || isLoading)
                .padding(.bottom, 1)
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
            )
        }
        .padding(12)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Markdown Theme

extension MarkdownUI.Theme {
    static let custom = Theme()
        .text {
            FontSize(15)
            ForegroundColor(.primary)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(13)
            BackgroundColor(Color(NSColor.controlBackgroundColor))
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .fontDesign(.monospaced)
                    .font(.system(size: 13))
                    .padding(14)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)
            )
        }
        .heading1 { configuration in
            configuration.label
                .markdownMargin(top: 20, bottom: 10)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(24)
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: 16, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(20)
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 12, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(17)
                }
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 6)
        }
        .paragraph { configuration in
            configuration.label
                .markdownMargin(top: 0, bottom: 12)
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
            .onChange(of: trigger) { newValue in
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
        textView.font = .systemFont(ofSize: 15)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.allowsUndo = true

        // Store callbacks
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

        // Initial height calculation
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

        // Update placeholder visibility
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

        // Draw placeholder when empty
        if string.isEmpty && !placeholderString.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: font ?? NSFont.systemFont(ofSize: 15)
            ]
            let inset = textContainerInset
            let rect = NSRect(x: inset.width, y: inset.height, width: bounds.width - inset.width * 2, height: bounds.height - inset.height * 2)
            placeholderString.draw(in: rect, withAttributes: attrs)
        }
    }

    override func keyDown(with event: NSEvent) {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags

        // Return/Enter key
        if keyCode == 36 {
            if modifiers.contains(.shift) {
                // Shift+Return: insert newline
                insertNewline(nil)
            } else {
                // Return alone: submit
                onSubmit?()
            }
            return
        }

        // Tab key
        if keyCode == 48 {
            if onTabKey?() == true {
                return
            }
        }

        // Arrow Up
        if keyCode == 126 {
            if onArrowUpKey?() == true {
                return
            }
        }

        // Arrow Down
        if keyCode == 125 {
            if onArrowDownKey?() == true {
                return
            }
        }

        // Escape
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
