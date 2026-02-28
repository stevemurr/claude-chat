<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%2B-black?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 13+">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/License-MIT-blue?style=for-the-badge" alt="MIT License">
</p>

<h1 align="center">ClaudeChat</h1>

<p align="center">
  <strong>A native macOS app for instant access to Claude AI</strong><br>
  Summon with a hotkey. Ask anything. Get back to work.
</p>

<p align="center">
  <a href="#-quick-start">Quick Start</a> •
  <a href="#-features">Features</a> •
  <a href="#%EF%B8%8F-installation">Installation</a> •
  <a href="#-usage">Usage</a>
</p>

---

## Why ClaudeChat?

You're deep in work. You need a quick answer from Claude. You don't want to:
- Open a browser tab
- Wait for a web app to load
- Lose your flow

**ClaudeChat lives in your menu bar.** One hotkey and you're chatting. Escape and it's gone.

---

## ⚡ Quick Start

```bash
# Clone & build
git clone https://github.com/stevemurr/claude-chat.git
cd claude-chat
brew install xcodegen && xcodegen generate
open ClaudeChat.xcodeproj  # Press Cmd+R to run
```

> **Requires:** [Claude Code CLI](https://claude.ai/code) installed

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🎯 **Global Hotkey** | `Cmd+Shift+Space` summons Claude from anywhere |
| ⚡ **Streaming** | See responses as they're generated |
| 🛠️ **Full Tools** | Web search, file access, everything Claude can do |
| 📝 **Daily Notes** | Rich text editor with markdown, tables, and code blocks |
| 🔗 **@Mentions** | Link between notes and groups with `@` |
| 🔍 **Command Palette** | `Cmd+K` to search everything |
| 📁 **Groups** | Organize content into collapsible pages |
| 👻 **Menu Bar Only** | No dock icon, no distractions |

---

## 🛠️ Installation

### Build from Source

```bash
git clone https://github.com/stevemurr/claude-chat.git
cd claude-chat
brew install xcodegen
xcodegen generate
open ClaudeChat.xcodeproj
# Press Cmd+R to build and run
```

### Download Release

Grab the latest `.app` from [Releases](https://github.com/stevemurr/claude-chat/releases).

---

## 🔧 Setup

### 1. Claude CLI Path

ClaudeChat auto-detects your Claude CLI. If not found, set it in Settings (⚙️):

```
~/.local/bin/claude        # npm global
/usr/local/bin/claude      # standard
/opt/homebrew/bin/claude   # homebrew
```

### 2. Accessibility Permission

For the global hotkey to work everywhere:

**System Settings → Privacy & Security → Accessibility → Add ClaudeChat.app**

---

## 🎮 Usage

| Action | Shortcut |
|--------|----------|
| Toggle window | `Cmd+Shift+Space` |
| Send message | `Enter` |
| New line | `Shift+Enter` |
| Command palette | `Cmd+K` |
| New chat | `Cmd+N` |
| Hide | `Escape` |

### Notes Editor

| Action | How |
|--------|-----|
| Slash commands | Type `/` for blocks |
| Link notes | Type `@` to mention |
| Create group | Select text + `Cmd+G` |
| Navigate back | `Escape` |

---

## 🏗️ Architecture

```
macOS/                          # macOS-specific code
├── AppDelegate.swift            # Hotkey, window management
├── ClaudeService.swift          # CLI subprocess wrapper
├── ContentView.swift            # Main UI
├── TiptapEditorView.swift       # WKWebView Tiptap wrapper
└── CommandPaletteView.swift
Shared/                         # Cross-platform code
├── Models/                      # ChatMessage, DailyNote, Block
├── Services/                    # DailyNoteService, SyncService, etc.
└── Views/                       # NotepadView, CalendarView, etc.
web/                            # Tiptap editor JS bundle
```

---

## 🤝 Contributing

PRs welcome! This is a personal project built for daily use.

---

## 📄 License

MIT — do whatever you want with it.

---

<p align="center">
  Built with SwiftUI • Powered by <a href="https://claude.ai/code">Claude Code CLI</a>
</p>
