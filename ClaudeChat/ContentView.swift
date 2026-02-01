import SwiftUI
import MarkdownUI

struct ContentView: View {
    @StateObject private var claudeService = ClaudeService()
    @StateObject private var historyService = ChatHistoryService()
    @State private var inputText = ""
    @State private var showHistory = false
    @State private var showSettings = false
    @State private var streamingText = ""
    @State private var isWorking = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            // History sidebar
            if showHistory {
                HistorySidebar(historyService: historyService, showHistory: $showHistory)
                    .frame(width: 220)

                Divider()
            }

            // Main chat area
            VStack(spacing: 0) {
                // Header
                ChatHeader(
                    showHistory: $showHistory,
                    showSettings: $showSettings,
                    onNewChat: {
                        historyService.newSession()
                        claudeService.resetConversation()
                    }
                )

                Divider()

                // Messages
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
                        }
                        .padding(20)
                    }
                    .onChange(of: historyService.currentSession.messages.count) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: claudeService.isLoading) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: streamingText) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                    .onChange(of: isWorking) { _ in
                        scrollToBottom(proxy: proxy)
                    }
                }

                Divider()

                // Input area
                InputArea(
                    inputText: $inputText,
                    isInputFocused: _isInputFocused,
                    isLoading: claudeService.isLoading,
                    onSend: sendMessage
                )
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusInput)) { _ in
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChat)) { _ in
            historyService.newSession()
            claudeService.resetConversation()
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if claudeService.isLoading {
                proxy.scrollTo("streaming", anchor: .bottom)
            } else if let lastMessage = historyService.currentSession.messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        historyService.addMessageToCurrentSession(userMessage)
        inputText = ""
        streamingText = ""
        isWorking = false

        Task {
            var addedMessages = Set<String>()

            let responses = await claudeService.sendMessage(text) { update in
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
        }
    }
}

// MARK: - Header

struct ChatHeader: View {
    @Binding var showHistory: Bool
    @Binding var showSettings: Bool
    let onNewChat: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { showHistory.toggle() }) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(showHistory ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle history")

            Text("Claude Chat")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()

            Button(action: onNewChat) {
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
            .help("Start new chat")

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
            FontSize(13)
            ForegroundColor(.primary)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(12)
            BackgroundColor(Color(NSColor.controlBackgroundColor))
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .fontDesign(.monospaced)
                    .font(.system(size: 12))
                    .padding(12)
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
                .markdownMargin(top: 16, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(20)
                }
        }
        .heading2 { configuration in
            configuration.label
                .markdownMargin(top: 12, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(17)
                }
        }
        .heading3 { configuration in
            configuration.label
                .markdownMargin(top: 8, bottom: 4)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(15)
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

#Preview {
    ContentView()
}
