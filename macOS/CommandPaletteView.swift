import SwiftUI
import AppKit

// MARK: - NSViewRepresentable Search Field

struct CommandPaletteSearchField: NSViewRepresentable {
    @Binding var text: String
    var onArrowUp: () -> Void
    var onArrowDown: () -> Void
    var onReturn: () -> Void
    var onEscape: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.placeholderString = "Search notes and chats..."
        textField.font = NSFont.systemFont(ofSize: 15)
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.delegate = context.coordinator
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true

        // Auto-focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            textField.window?.makeFirstResponder(textField)
        }

        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandPaletteSearchField

        init(_ parent: CommandPaletteSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                parent.text = textField.stringValue
            }
        }

        // Intercept Return, Escape, and arrow keys via the field editor's command dispatch
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onReturn()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onEscape()
                return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                parent.onArrowUp()
                return true
            }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                parent.onArrowDown()
                return true
            }
            return false
        }
    }
}

// MARK: - Main View

struct CommandPaletteView: View {
    @ObservedObject var service: CommandPaletteService

    var onSelect: (CommandPaletteItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)

                CommandPaletteSearchField(
                    text: $service.query,
                    onArrowUp: { service.moveUp() },
                    onArrowDown: { service.moveDown() },
                    onReturn: { selectCurrent() },
                    onEscape: { service.dismiss() }
                )
                .frame(height: 22)

                if !service.query.isEmpty {
                    Button(action: { service.query = ""; service.search() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            // Results
            if service.results.isEmpty {
                CommandPaletteEmptyState(hasQuery: !service.query.isEmpty)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(service.results.enumerated()), id: \.element.id) { index, item in
                                CommandPaletteRow(
                                    item: item,
                                    isSelected: index == service.selectedIndex
                                )
                                .id(index)
                                .onTapGesture {
                                    service.selectedIndex = index
                                    selectCurrent()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: service.selectedIndex) { newIndex in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }

            Divider()

            // Footer
            CommandPaletteFooter()
        }
        .frame(width: 440)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 4)
        .onChange(of: service.query) { _ in
            service.search()
        }
    }

    private func selectCurrent() {
        guard !service.results.isEmpty,
              service.selectedIndex < service.results.count else { return }
        let item = service.results[service.selectedIndex]
        onSelect(item)
    }
}

// MARK: - Row

struct CommandPaletteRow: View {
    let item: CommandPaletteItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 13))
                .foregroundColor(iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if item.type != .action {
                        Text(item.type == .dailyNote ? "Note" : "Chat")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(NSColor.separatorColor).opacity(0.3))
                            .cornerRadius(3)
                    }
                }

                if !item.preview.isEmpty {
                    Text(item.preview)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if item.type == .action {
                Text("Action")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(NSColor.separatorColor).opacity(0.3))
                    .cornerRadius(3)
            } else {
                Text(item.timestamp.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }

    private var iconName: String {
        switch item.type {
        case .action:
            if item.action == .newNote { return "calendar.badge.plus" }
            return "plus.bubble"
        case .dailyNote:
            return "calendar"
        case .chat:
            return "bubble.left.fill"
        }
    }

    private var iconColor: Color {
        switch item.type {
        case .action: return .green
        case .dailyNote: return .orange
        case .chat: return .blue
        }
    }
}

// MARK: - Empty State

struct CommandPaletteEmptyState: View {
    let hasQuery: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundColor(.secondary.opacity(0.5))

            Text(hasQuery ? "No results found" : "No notes or chats yet")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Footer

struct CommandPaletteFooter: View {
    var body: some View {
        HStack(spacing: 16) {
            keyHint(keys: "↑↓", label: "navigate")
            keyHint(keys: "↩", label: "open")
            keyHint(keys: "esc", label: "close")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func keyHint(keys: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color(NSColor.separatorColor).opacity(0.3))
                .cornerRadius(3)

            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}
