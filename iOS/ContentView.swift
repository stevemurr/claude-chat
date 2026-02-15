import SwiftUI
import MarkdownUI
import Combine
import UIKit

// MARK: - Growing Text View (iMessage-style)

struct GrowingTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var placeholder: String = "Message"
    var maxHeight: CGFloat = 150
    var minHeight: CGFloat = 36

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
        recalculateHeight(textView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func recalculateHeight(_ textView: UITextView) {
        let size = textView.sizeThatFits(CGSize(width: textView.frame.width, height: .greatestFiniteMagnitude))
        let newHeight = min(max(size.height, minHeight), maxHeight)

        if textView.frame.width > 0 && height != newHeight {
            DispatchQueue.main.async {
                self.height = newHeight
                textView.isScrollEnabled = newHeight >= maxHeight
            }
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingTextView

        init(_ parent: GrowingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.recalculateHeight(textView)
        }
    }
}

// MARK: - Keyboard Observer

class KeyboardObserver: ObservableObject {
    @Published var keyboardHeight: CGFloat = 0
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification))
            .compactMap { notification -> CGFloat? in
                guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                    return nil
                }
                // Only return height if keyboard is actually showing (not just changing)
                return frame.origin.y < UIScreen.main.bounds.height ? frame.height : 0
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] height in
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.keyboardHeight = height
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    self?.keyboardHeight = 0
                }
            }
            .store(in: &cancellables)
    }
}

struct ContentView: View {
    @StateObject private var claudeAPIService = ClaudeAPIService()
    @StateObject private var dailyNoteService = DailyNoteService()

    // 0 = Calendar, 1 = Note, 2 = Chat
    @State private var currentPage = 1
    @State private var showSettings = false

    var body: some View {
        TabView(selection: $currentPage) {
            // Left: Calendar (swipe right to reveal)
            CalendarPageView(dailyNoteService: dailyNoteService, onDateSelected: {
                withAnimation {
                    currentPage = 1
                }
            })
            .tag(0)

            // Center: Note Editor (default view)
            NotePageView(
                dailyNoteService: dailyNoteService,
                showSettings: $showSettings,
                currentPage: $currentPage
            )
            .tag(1)

            // Right: Chat (swipe left to reveal)
            ChatPageView(
                claudeService: claudeAPIService,
                dailyNoteService: dailyNoteService,
                currentPage: $currentPage
            )
            .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea(.keyboard) // Disable automatic keyboard avoidance - ChatView handles it manually
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

// MARK: - Calendar Page

struct CalendarPageView: View {
    @ObservedObject var dailyNoteService: DailyNoteService
    var onDateSelected: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)

                Spacer()

                Text("Calendar")
                    .font(.headline)

                Spacer()

                Button(action: onDateSelected) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(UIColor.systemBackground))

            Divider()

            // Calendar view fills remaining space
            CalendarView(dailyNoteService: dailyNoteService, onDateTap: {
                onDateSelected()
            })
            .padding(.horizontal)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}

// MARK: - Note Page

struct NotePageView: View {
    @ObservedObject var dailyNoteService: DailyNoteService
    @Binding var showSettings: Bool
    @Binding var currentPage: Int

    var body: some View {
        VStack(spacing: 0) {
            // Header with sidebar toggle buttons
            HStack {
                Button(action: {
                    withAnimation {
                        currentPage = 0
                    }
                }) {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(dailyNoteService.currentNote.shortDisplayTitle)
                    .font(.headline)

                Spacer()

                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.secondary)
                }

                Button(action: {
                    withAnimation {
                        currentPage = 2
                    }
                }) {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 8)
            }
            .padding()
            .background(Color(UIColor.systemBackground))

            Divider()

            // Note editor
            NotepadContentView(dailyNoteService: dailyNoteService)
        }
        .background(Color(UIColor.systemBackground))
    }
}

// MARK: - Chat Page

struct ChatPageView: View {
    @ObservedObject var claudeService: ClaudeAPIService
    @ObservedObject var dailyNoteService: DailyNoteService
    @Binding var currentPage: Int

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: {
                    withAnimation {
                        currentPage = 1
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("Chat")
                    .font(.headline)

                Spacer()

                Button(action: { dailyNoteService.clearCurrentNoteChat() }) {
                    Image(systemName: "trash")
                        .foregroundColor(.secondary)
                }
                .disabled(dailyNoteService.currentNote.chatMessages.isEmpty)

                Image(systemName: "sidebar.trailing")
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
                    .padding(.leading, 8)
            }
            .padding()
            .background(Color(UIColor.systemBackground))

            Divider()

            // Chat content
            ChatView(
                claudeService: claudeService,
                dailyNoteService: dailyNoteService
            )
        }
        .background(Color(UIColor.systemBackground))
    }
}

// MARK: - Chat View

struct ChatView: View {
    @ObservedObject var claudeService: ClaudeAPIService
    @ObservedObject var dailyNoteService: DailyNoteService
    @StateObject private var keyboardObserver = KeyboardObserver()

    @State private var inputText = ""
    @State private var streamingText = ""
    @State private var isWorking = false
    @State private var textEditorHeight: CGFloat = 36
    @FocusState private var isInputFocused: Bool

    private let minHeight: CGFloat = 36
    private let maxHeight: CGFloat = 150

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(dailyNoteService.currentNote.chatMessages) { message in
                            ChatMessageBubble(message: message)
                                .id(message.id)
                        }

                        if claudeService.isLoading {
                            StreamingBubble(text: streamingText, isWorking: isWorking)
                                .id("streaming")
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding()
                }
                .onChange(of: dailyNoteService.currentNote.chatMessages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: streamingText) { _, _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: keyboardObserver.keyboardHeight) { _, _ in
                    // Scroll to bottom when keyboard appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: textEditorHeight) { _, _ in
                    // Scroll to bottom when input grows
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            // Input area (Divider + field grouped together)
            VStack(spacing: 0) {
                Divider()

                HStack(alignment: .bottom, spacing: 12) {
                    ZStack(alignment: .topLeading) {
                        // Placeholder
                        if inputText.isEmpty {
                            Text("Ask Claude...")
                                .foregroundColor(Color(UIColor.placeholderText))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                        }

                        // Growing text input
                        GrowingTextView(
                            text: $inputText,
                            height: $textEditorHeight,
                            placeholder: "Ask Claude...",
                            maxHeight: maxHeight,
                            minHeight: minHeight
                        )
                        .frame(height: textEditorHeight)
                    }
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(20)

                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(inputText.isEmpty || claudeService.isLoading ? .gray : .accentColor)
                    }
                    .disabled(inputText.isEmpty || claudeService.isLoading)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .padding(.bottom, keyboardBottomPadding)
            }
            .background(Color(UIColor.systemBackground))
        }
    }

    /// Calculate bottom padding to push input above keyboard
    private var keyboardBottomPadding: CGFloat {
        let keyboardHeight = keyboardObserver.keyboardHeight
        guard keyboardHeight > 0 else { return 0 }
        // Approximate safe area bottom - keyboard usually covers it
        return max(0, keyboardHeight - 34)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Build context with current note and nearby dates
        let currentNote = dailyNoteService.currentNote
        var contextParts: [String] = []

        // Add yesterday's note if it exists
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: dailyNoteService.selectedDate),
           let yesterdayNote = dailyNoteService.note(for: yesterday),
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
        if let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: dailyNoteService.selectedDate),
           let tomorrowNote = dailyNoteService.note(for: tomorrow),
           tomorrowNote.hasContent {
            contextParts.append("""
                --- Tomorrow's Note: \(tomorrowNote.displayTitle) (date: \(tomorrowNote.dateKey)) ---
                \(tomorrowNote.content)
                """)
        }

        let noteContext = contextParts.joined(separator: "\n\n")

        // Add user message
        let userMessage = ChatMessage(role: .user, content: text)
        dailyNoteService.currentNote.chatMessages.append(userMessage)

        let shouldContinue = dailyNoteService.currentNote.conversationStarted
        inputText = ""
        streamingText = ""
        isWorking = false

        Task {
            var addedMessages = Set<String>()

            let responses = await claudeService.sendMessage(
                text,
                noteContext: noteContext,
                continueConversation: shouldContinue
            ) { update in
                streamingText = update.text
                isWorking = update.isWorking

                if update.isComplete && !update.text.isEmpty && !addedMessages.contains(update.text) {
                    addedMessages.insert(update.text)
                    let (cleanedText, toolUpdates) = processResponseWithNoteUpdates(update.text)

                    // Add tool result messages for each note update
                    for toolUpdate in toolUpdates {
                        dailyNoteService.addToolResultMessage(
                            toolName: "note_update",
                            output: "Updated note \(toolUpdate.dateKey):\n\n\(toolUpdate.content)"
                        )
                    }

                    if !cleanedText.isEmpty {
                        let assistantMessage = ChatMessage(role: .assistant, content: cleanedText)
                        dailyNoteService.currentNote.chatMessages.append(assistantMessage)
                    }
                    streamingText = ""
                }
            }

            dailyNoteService.currentNote.conversationStarted = true

            if let responses = responses {
                for response in responses {
                    if !response.isEmpty && !addedMessages.contains(response) {
                        let (cleanedText, toolUpdates) = processResponseWithNoteUpdates(response)

                        // Add tool result messages for each note update
                        for toolUpdate in toolUpdates {
                            dailyNoteService.addToolResultMessage(
                                toolName: "note_update",
                                output: "Updated note \(toolUpdate.dateKey):\n\n\(toolUpdate.content)"
                            )
                        }

                        if !cleanedText.isEmpty {
                            let assistantMessage = ChatMessage(role: .assistant, content: cleanedText)
                            dailyNoteService.currentNote.chatMessages.append(assistantMessage)
                        }
                    }
                }
            } else if let error = claudeService.lastError {
                let errorMessage = ChatMessage(role: .assistant, content: "Error: \(error)")
                dailyNoteService.currentNote.chatMessages.append(errorMessage)
            }

            streamingText = ""
            isWorking = false
            dailyNoteService.saveCurrentNote()
        }
    }

    private func processResponseWithNoteUpdates(_ text: String) -> (cleanedText: String, toolUpdates: [(dateKey: String, content: String)]) {
        let (updates, cleanedText) = NoteUpdateParser.parse(text)
        var toolUpdates: [(dateKey: String, content: String)] = []

        for update in updates {
            if var existingNote = dailyNoteService.notesByDate[update.dateKey] {
                existingNote.content = update.content
                existingNote.updatedAt = Date()
                dailyNoteService.notesByDate[update.dateKey] = existingNote

                if dailyNoteService.currentNote.dateKey == update.dateKey {
                    dailyNoteService.currentNote.content = update.content
                    dailyNoteService.currentNote.updatedAt = Date()
                }
            } else {
                let newNote = DailyNote(dateKey: update.dateKey, content: update.content)
                dailyNoteService.notesByDate[update.dateKey] = newNote
            }

            NotificationCenter.default.post(
                name: .noteUpdated,
                object: nil,
                userInfo: ["dateKey": update.dateKey]
            )

            toolUpdates.append((dateKey: update.dateKey, content: update.content))
        }

        if !updates.isEmpty {
            dailyNoteService.saveNotes()
        }

        return (cleanedText, toolUpdates)
    }
}

// MARK: - Tool Result Block (collapsible) - iOS

struct ToolResultBlockiOS: View {
    let toolName: String
    let output: String
    @State private var isExpanded = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                // Header - always visible
                Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: "wrench.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Text(toolName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Expanded content
                if isExpanded {
                    Divider()
                        .padding(.horizontal, 12)

                    Markdown(output)
                        .textSelection(.enabled)
                        .font(.system(size: 13))
                        .padding(12)
                }
            }
            .frame(maxWidth: 300, alignment: .leading)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)

            Spacer()
        }
    }
}

// MARK: - Chat Message Bubble

struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        // Check if this is a tool result message
        if message.isToolResult, let toolName = message.toolName, let toolOutput = message.toolOutput {
            ToolResultBlockiOS(toolName: toolName, output: toolOutput)
        } else {
            regularMessageView
        }
    }

    private var regularMessageView: some View {
        HStack {
            if message.role == .user { Spacer() }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.role == .user ? "You" : "Claude")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Markdown(message.content)
                    .textSelection(.enabled)
                    .padding(12)
                    .background(backgroundColor)
                    .cornerRadius(16)
            }
            .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer() }
        }
    }

    private var backgroundColor: Color {
        message.role == .user
            ? Color.accentColor.opacity(0.2)
            : Color(UIColor.secondarySystemBackground)
    }
}

// MARK: - Streaming Bubble

struct StreamingBubble: View {
    let text: String
    let isWorking: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Claude")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    ProgressView()
                        .scaleEffect(0.7)
                }

                if text.isEmpty {
                    Text(isWorking ? "Working..." : "Thinking...")
                        .foregroundColor(.secondary)
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                } else {
                    Markdown(text)
                        .textSelection(.enabled)
                        .padding(12)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(16)
                }
            }
            .frame(maxWidth: 300, alignment: .leading)

            Spacer()
        }
    }
}

#Preview {
    ContentView()
}
