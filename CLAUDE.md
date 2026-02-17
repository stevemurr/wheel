# CLAUDE.md

This file provides guidance for Claude when working on the Wheel Browser codebase.

## Project Overview

Wheel is a macOS browser built with Swift and SwiftUI. It features:
- WebKit-based web rendering
- AI assistant sidebar powered by Claude
- Tab management with collapsible sidebar
- Fuzzy search for browsing history

## Build & Run

```bash
cd WheelBrowser
swift build
swift run WheelBrowser
```

## Project Structure

```
WheelBrowser/
├── Package.swift              # Swift package manifest
└── Sources/WheelBrowser/
    ├── WheelBrowserApp.swift  # App entry point and menu setup
    ├── ContentView.swift      # Main window layout
    ├── NavigationBar.swift    # URL bar and navigation controls
    ├── TabBar.swift           # Left sidebar with tabs
    ├── WebViewRepresentable.swift  # WKWebView wrapper
    ├── Chat/
    │   ├── ChatView.swift     # AI sidebar panel
    │   ├── MessageBubble.swift # Chat message display
    │   └── AgentManager.swift # AI agent logic
    ├── History/
    │   ├── BrowsingHistory.swift      # History storage
    │   ├── FuzzySearch.swift          # Fuzzy matching algorithm
    │   └── AddressBarSuggestions.swift # URL suggestions UI
    └── Settings/
        └── AppSettings.swift  # User preferences
```

## Key Design Decisions

### AI Sidebar
- Floats as a rounded panel over web content only (not title bar or nav bar)
- Hover-to-reveal: appears when hovering right edge of page
- Uses native macOS colors (`windowBackgroundColor`, `controlBackgroundColor`)
- No blur effect on web content (WKWebView doesn't support sibling view blur)

### Tab Sidebar
- Left side, supports expanded/collapsed modes
- State persisted via `@AppStorage`
- Toggle with `Cmd+Shift+S`

### Address Bar
- Fuzzy search on browsing history
- Debounced search (50ms)
- Keyboard navigation (up/down/enter/escape)
- History stored in `~/Library/Application Support/WheelBrowser/history.json`

## Common Tasks

### Adding a new keyboard shortcut
1. Add notification name in `WheelBrowserApp.swift`
2. Add menu item with `keyboardShortcut()` modifier
3. Handle notification in `ContentView.swift`

### Modifying AI sidebar appearance
- `ChatView.swift` - overall panel layout and styling
- `MessageBubble.swift` - individual message appearance
- Panel uses `Color(nsColor: .windowBackgroundColor)` for native appearance

### Adding new settings
1. Add `@AppStorage` property in `Settings/AppSettings.swift`
2. Access via `AppSettings.shared` throughout the app
