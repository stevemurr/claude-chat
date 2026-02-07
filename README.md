# ClaudeChat

A lightweight macOS app for quick Q&A with Claude via the Claude Code CLI. Summon it with a global hotkey for fast, focused conversations.

![ClaudeChat Demo](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Global Hotkey**: Summon the chat window from anywhere (default: `Cmd+Shift+Space`)
- **Streaming Responses**: See Claude's responses as they're generated
- **Tool Support**: Full access to Claude's tools including web search
- **Markdown Rendering**: Code blocks, headers, lists, and more
- **Conversation History**: Browse and resume past conversations
- **Floating Window**: Stays above other windows when focused
- **No Dock Icon**: Runs as a menu bar agent
- **Notepad**: Rich text notes with Tiptap editor, AI-generated titles, and local persistence
- **Command Palette**: Fuzzy search across notes and chat history (`Cmd+K`)

## Requirements

- macOS 13.0 or later
- [Claude Code CLI](https://claude.ai/code) installed
- Xcode 15+ (for building)

## Installation

### Option 1: Build from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/stevemurr/claude-chat.git
   cd claude-chat
   ```

2. Install xcodegen (if not installed):
   ```bash
   brew install xcodegen
   ```

3. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

4. Open and build:
   ```bash
   open ClaudeChat.xcodeproj
   ```

5. Press `Cmd+R` to build and run

### Option 2: Download Release

Download the latest release from the [Releases](https://github.com/stevemurr/claude-chat/releases) page.

## Setup

### Claude CLI Path

ClaudeChat will attempt to auto-detect your Claude CLI installation. If it's not found automatically, you can set the path manually in Settings:

1. Open ClaudeChat
2. Click the gear icon (⚙️) in the header
3. Set the path to your Claude CLI (e.g., `~/.local/bin/claude`)

Common installation paths:
- `~/.local/bin/claude` (npm global install)
- `/usr/local/bin/claude`
- `/opt/homebrew/bin/claude`

### Accessibility Permissions

For the global hotkey to work when other apps are focused, you need to grant accessibility permissions:

1. Go to **System Settings → Privacy & Security → Accessibility**
2. Click the **+** button
3. Add **ClaudeChat.app** (or **Xcode** if running from Xcode)
4. Enable the toggle

## Usage

| Action | Shortcut |
|--------|----------|
| Toggle window | `Cmd+Shift+Space` (configurable) |
| New chat | `Cmd+N` |
| Send message | `Enter` |
| Newline in message | `Shift+Enter` |
| Hide window | `Escape` |
| Command palette | `Cmd+K` |

## Configuration

Click the gear icon in the header to access settings:

- **Global Hotkey**: Click the hotkey box and press your desired key combination
- **Claude CLI Path**: Path to your Claude Code CLI installation

## Architecture

```
ClaudeChat/
├── ClaudeChatApp.swift      # App entry point
├── AppDelegate.swift        # Hotkey registration, window management
├── ContentView.swift        # Main chat UI with tab switching
├── ChatMessage.swift        # Message model
├── ChatSession.swift        # Session model and history
├── ClaudeService.swift      # Claude CLI subprocess wrapper
├── SettingsView.swift       # Settings UI and manager
├── Note.swift               # Note model with block support
├── Block.swift              # Block-based content model
├── NoteService.swift        # Note persistence and management
├── NotepadView.swift        # Notes sidebar and content view
├── TiptapEditorView.swift   # WKWebView wrapper for Tiptap
├── TitleService.swift       # AI-powered title generation
├── CommandPalette.swift     # Fuzzy search service
├── CommandPaletteView.swift # Search overlay UI
└── Resources/
    ├── tiptap-editor.html   # Editor HTML template
    └── tiptap-bundle.js     # Bundled Tiptap editor
```

## How It Works

ClaudeChat wraps the Claude Code CLI (`claude -p`) in a native macOS interface:

1. Messages are sent via `claude -p "<message>" --output-format stream-json`
2. Responses are streamed and rendered in real-time
3. Conversation context is maintained using the `-c` flag
4. Full tool access is enabled with `--tools default --dangerously-skip-permissions`

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Built with [SwiftUI](https://developer.apple.com/xcode/swiftui/)
- Markdown rendering by [MarkdownUI](https://github.com/gonzalezreal/swift-markdown-ui)
- Powered by [Claude Code CLI](https://claude.ai/code)
