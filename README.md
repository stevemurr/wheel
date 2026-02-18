# Wheel Browser

A modern macOS browser built with Swift and SwiftUI, featuring an integrated AI assistant, semantic search, and workspace management.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange?logo=swift)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

### OmniBar - Unified Input System

The OmniBar is a tri-modal input bar at the bottom of the screen. Press **Tab** to cycle between modes:

| Mode | Icon | Description |
|------|------|-------------|
| **Address** | Search | Navigate to URLs or search with fuzzy history matching |
| **Chat** | Sparkles | AI assistant with page context and @mentions |
| **Semantic** | Brain | Vector-based semantic search over browsing history |

### AI Assistant

- **Context-Aware Chat**: Ask questions about the current page with full content extraction
- **@Mention System**: Reference multiple sources in your queries
  - `@Page` - Current page context (default)
  - `@[Tab Name]` - Content from other open tabs
  - `@[History Result]` - Pages from semantic search
- **Streaming Responses**: Real-time response streaming with markdown rendering
- **Agent Studio**: Create custom AI agents with personalized system prompts and skills

### Semantic Search

- **Vector Embeddings**: Uses Apple's NLEmbedding for 512-dimensional sentence embeddings
- **Automatic Indexing**: Pages are indexed as you browse
- **Similarity Search**: Find pages by meaning, not just keywords
- **Persistent Index**: Search index persists across app restarts

### Workspaces

- **Organize Your Work**: Group tabs into separate workspaces
- **Custom Appearance**: Choose icons and colors for each workspace
- **Agent Binding**: Assign a default AI agent per workspace
- **State Persistence**: Tabs and workspace state saved automatically

### Additional Features

- **Tab Management**: Full tab support with reopen closed tabs (Cmd+Shift+T)
- **Download Manager**: Track and manage downloads with progress indicators
- **Content Blocking**: Built-in ad blocking with category controls
- **Picture-in-Picture**: Float videos over other windows (Cmd+Shift+P)
- **Find in Page**: Full-text search with highlighting (Cmd+F)
- **Zoom Controls**: Page zoom with keyboard shortcuts
- **Native macOS Design**: Built with SwiftUI for a clean, native experience

## Requirements

- macOS 14.0+
- Xcode 15.0+
- Swift 5.9+

## Building

```bash
cd WheelBrowser
swift build
```

## Running

```bash
swift run WheelBrowser
```

## Configuration

### LLM Setup

Wheel supports any OpenAI-compatible API endpoint. Configure in Settings:

1. **Local (Ollama)**: Default endpoint `http://localhost:11434/v1`
2. **Cloud APIs**: Set your endpoint URL and API key

### Settings Location

Settings are stored in:
- **Preferences**: macOS UserDefaults
- **API Keys**: macOS Keychain (secure)
- **Data**: `~/Library/Application Support/WheelBrowser/`

## Keyboard Shortcuts

### Navigation
| Shortcut | Action |
|----------|--------|
| `Cmd+L` | Focus address bar |
| `Cmd+R` | Reload page |
| `Cmd+.` | Stop loading |
| `Cmd+[` | Go back |
| `Cmd+]` | Go forward |

### Tabs
| Shortcut | Action |
|----------|--------|
| `Cmd+T` | New tab |
| `Cmd+W` | Close tab |
| `Cmd+1-9` | Switch to tab 1-9 |
| `Cmd+Shift+[` | Previous tab |
| `Cmd+Shift+]` | Next tab |
| `Cmd+Shift+T` | Reopen closed tab |

### AI & Search
| Shortcut | Action |
|----------|--------|
| `Cmd+K` | Focus AI chat |
| `Cmd+J` | Focus semantic search |
| `Tab` | Cycle OmniBar modes |

### View
| Shortcut | Action |
|----------|--------|
| `Cmd+Shift+S` | Toggle tab sidebar |
| `Cmd+F` | Find in page |
| `Cmd+D` | Toggle downloads |
| `Cmd+Shift+P` | Picture-in-Picture |
| `Cmd++` | Zoom in |
| `Cmd+-` | Zoom out |
| `Cmd+0` | Reset zoom |

## Architecture

```
WheelBrowser/
├── Package.swift
└── Sources/WheelBrowser/
    ├── WheelBrowserApp.swift      # App entry point
    ├── ContentView.swift          # Main window layout
    ├── BrowserState.swift         # Tab & state management
    ├── OmniBar/
    │   ├── OmniBar.swift          # Unified input bar
    │   ├── OmniBarState.swift     # OmniBar state management
    │   ├── MentionTypes.swift     # @mention system types
    │   ├── MentionChip.swift      # Mention UI components
    │   └── ...
    ├── Letta/
    │   └── AgentManager.swift     # AI chat integration
    ├── SemanticSearch/
    │   └── SemanticSearchManager.swift  # Vector search
    ├── Workspaces/
    │   └── WorkspaceManager.swift # Workspace management
    ├── History/
    │   ├── BrowsingHistory.swift  # History storage
    │   └── FuzzySearch.swift      # Fuzzy matching
    ├── ContentBlocking/
    │   └── ContentBlockerManager.swift  # Ad blocking
    ├── Downloads/
    │   └── DownloadManager.swift  # Download handling
    └── Settings/
        └── AppSettings.swift      # User preferences
```

## License

MIT
