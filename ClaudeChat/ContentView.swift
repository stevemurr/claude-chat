import SwiftUI
import MarkdownUI

enum AppMode {
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
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var streamingText = ""
    @State private var isWorking = false
    @State private var isAtBottom = true
    @State private var showScrollButton = false
    @State private var appMode: AppMode = .chat
    @State private var showAutocomplete = false
    @State private var autocompleteQuery = ""
    @State private var autocompleteSelectedIndex = 0
    @FocusState private var isInputFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar - conditional based on mode
            if showHistory {
                Group {
                    switch appMode {
                    case .chat:
                        HistorySidebar(historyService: historyService, showHistory: $showHistory)
                    case .notepad:
                        NoteSidebar(noteService: noteService)
                    }
                }
                .frame(width: 220)

                Divider()
            }

            // Main content area
            VStack(spacing: 0) {
                // Unified Header
                UnifiedHeader(
                    showHistory: $showHistory,
                    showSettings: $showSettings,
                    appMode: $appMode,
                    onNew: {
                        switch appMode {
                        case .chat:
                            historyService.newSession()
                            claudeService.resetConversation()
                        case .notepad:
                            noteService.newNote()
                        }
                    }
                )

                Divider()

                // Content area - conditional based on mode
                switch appMode {
                case .chat:
                    chatContent

                case .notepad:
                    NotepadContentView(noteService: noteService, titleService: titleService)
                }

                // Bottom mode bar
                HStack {
                    Spacer()
                    HStack(spacing: 2) {
                        ModeChip(label: "Chat", icon: "bubble.left.fill",
                                 isActive: appMode == .chat, color: .orange) { appMode = .chat }
                        ModeChip(label: "Notes", icon: "doc.text",
                                 isActive: appMode == .notepad, color: .blue) { appMode = .notepad }
                    }
                    .padding(3)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                    .cornerRadius(8)
                    Spacer()
                }
                .padding(.vertical, 6)
                .background(appMode == .chat ? Color.orange.opacity(0.06) : Color.blue.opacity(0.06))
                .overlay(alignment: .top) {
                    (appMode == .chat ? Color.orange : Color.blue).opacity(0.2).frame(height: 1)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            isInputFocused = true
            commandPaletteService.configure(noteService: noteService, historyService: historyService)
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusInput)) { _ in
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChat)) { _ in
            if appMode == .chat {
                historyService.newSession()
                claudeService.resetConversation()
                isInputFocused = true
            } else {
                noteService.newNote()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newNote)) { _ in
            appMode = .notepad
            noteService.newNote()
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
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .overlay {
            if commandPaletteService.isVisible {
                ZStack(alignment: .top) {
                    // Backdrop
                    Color.black.opacity(0.45)
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
                        onSend: sendMessage
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
                isInputFocused = true
            case .newNote:
                appMode = .notepad
                noteService.newNote()
            case .none:
                break
            }
        case .note:
            if let note = item.note {
                appMode = .notepad
                noteService.loadNote(note)
            }
        case .chat:
            if let session = item.session {
                appMode = .chat
                historyService.loadSession(session)
                claudeService.resetConversation()
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

// MARK: - Unified Header

struct UnifiedHeader: View {
    @Binding var showHistory: Bool
    @Binding var showSettings: Bool
    @Binding var appMode: AppMode
    let onNew: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { showHistory.toggle() }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(showHistory ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle sidebar")

            Spacer()

            Button(action: onNew) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("New")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .help(appMode == .chat ? "Start new chat" : "Create new note")

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
}

struct ModeChip: View {
    let label: String
    let icon: String
    let isActive: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isActive ? color : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? color.opacity(0.15) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History Sidebar

struct HistorySidebar: View {
    @ObservedObject var historyService: ChatHistoryService
    @Binding var showHistory: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(historyService.sessions) { session in
                        SessionRow(
                            session: session,
                            isSelected: session.id == historyService.currentSession.id,
                            onSelect: {
                                historyService.loadSession(session)
                            },
                            onDelete: {
                                historyService.deleteSession(session)
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

struct SessionRow: View {
    let session: ChatSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .foregroundColor(.primary)

                Text(session.updatedAt.formatted(.relative(presentation: .named)))
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
                .font(.system(size: 11, weight: .semibold))
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
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return Color(red: 0.22, green: 0.45, blue: 0.85).opacity(0.08)
        case .assistant:
            return Color(red: 0.55, green: 0.36, blue: 0.68).opacity(0.06)
        }
    }

    private var headerColor: Color {
        switch message.role {
        case .user:
            return Color(red: 0.22, green: 0.45, blue: 0.85).opacity(0.12)
        case .assistant:
            return Color(red: 0.55, green: 0.36, blue: 0.68).opacity(0.10)
        }
    }

    private var borderColor: Color {
        switch message.role {
        case .user:
            return Color(red: 0.22, green: 0.45, blue: 0.85).opacity(0.25)
        case .assistant:
            return Color(red: 0.55, green: 0.36, blue: 0.68).opacity(0.20)
        }
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
    @State private var spinnerRotation = 0.0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    let spinnerTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Claude", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()

                // Status indicator
                if isWorking {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                            .rotationEffect(.degrees(spinnerRotation))
                        Text("Working...")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.orange)
                    }
                } else {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Streaming")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isWorking ? Color.orange.opacity(0.10) : Color(red: 0.55, green: 0.36, blue: 0.68).opacity(0.10))

            if text.isEmpty {
                // Show loading dots or working message
                if isWorking {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Running tools...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                } else {
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(Color.secondary)
                                .frame(width: 6, height: 6)
                                .opacity(dotCount == index ? 1 : 0.3)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                }
            } else {
                Markdown(text)
                    .textSelection(.enabled)
                    .markdownTheme(.custom)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .background(isWorking ? Color.orange.opacity(0.04) : Color(red: 0.55, green: 0.36, blue: 0.68).opacity(0.06))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isWorking ? Color.orange.opacity(0.25) : Color(red: 0.55, green: 0.36, blue: 0.68).opacity(0.20), lineWidth: 1)
        )
        .onReceive(timer) { _ in
            dotCount = (dotCount + 1) % 3
        }
        .onReceive(spinnerTimer) { _ in
            spinnerRotation += 15
        }
    }
}

// MARK: - Input Area

struct InputArea: View {
    @Binding var inputText: String
    @FocusState var isInputFocused: Bool
    let isLoading: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                TextField("Ask Claude...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .lineLimit(1...8)
                    .focused($isInputFocused)
                    .frame(minHeight: 26)
                    .onSubmit {
                        if !NSEvent.modifierFlags.contains(.shift) {
                            onSend()
                        }
                    }

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(inputText.isEmpty || isLoading ? .secondary.opacity(0.4) : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || isLoading)
            }
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(22)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
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

#Preview {
    ContentView()
}
