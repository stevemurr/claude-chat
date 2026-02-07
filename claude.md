# ClaudeChat Development Guide

## Project Overview

ClaudeChat is a native macOS app that provides a floating chat interface for Claude Code CLI. It runs as a menu bar agent with global hotkey support.

## Tech Stack

- **Swift 5.9** / **SwiftUI** - Native macOS app
- **xcodegen** - Xcode project generation from `project.yml`
- **MarkdownUI** - Markdown rendering for chat responses
- **Tiptap** - Rich text editor for notes (via WKWebView)

## Key Architecture

### Chat System
- `ClaudeService` spawns `claude -p` subprocess with `--output-format stream-json`
- Streaming JSON responses are parsed in real-time
- Sessions persist with conversation ID for context continuity

### Notes System
- `NoteService` manages note CRUD with JSON persistence
- `TiptapEditorView` wraps a WebView running Tiptap editor
- Notes stored as markdown with block-based internal representation
- `TitleService` uses Claude to auto-generate note titles

### Command Palette
- `CommandPaletteService` provides fuzzy search across notes and chats
- Keyboard-driven navigation with `Cmd+K` to open

## Building

```bash
# Generate Xcode project
xcodegen generate

# Open in Xcode
open ClaudeChat.xcodeproj

# Build and run
# Cmd+R in Xcode
```

## Rebuilding Tiptap Bundle

```bash
cd web
npm install
./build.sh
```

Output goes to `ClaudeChat/Resources/tiptap-bundle.js`.

## File Locations

- **Chat history**: `~/Library/Application Support/ClaudeChat/chat_history.json`
- **Notes**: `~/Library/Application Support/ClaudeChat/notes.json`
- **Settings**: UserDefaults (hotkey, CLI path)

## Important Patterns

- Global hotkey uses `CGEvent` taps (requires Accessibility permission)
- App runs as `LSUIElement` (no dock icon, menu bar only)
- Sandbox disabled for CLI subprocess and global events
