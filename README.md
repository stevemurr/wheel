# Wheel Browser

A modern macOS browser built with Swift and SwiftUI, featuring an integrated AI assistant.

## Features

- **Native macOS Design**: Built with SwiftUI for a clean, native experience
- **AI Assistant Sidebar**: Hover-activated AI chat panel that overlays the page content
  - Ask questions about the current page
  - Powered by Claude AI
  - Sleek floating panel design with rounded corners
- **Collapsible Tab Sidebar**: Toggle between expanded (full names) and collapsed (icons only) modes with `Cmd+Shift+S`
- **Fuzzy Search Address Bar**: Search your browsing history with intelligent fuzzy matching
- **Keyboard Shortcuts**: Full keyboard navigation support

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

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Cmd+T` | New tab |
| `Cmd+W` | Close tab |
| `Cmd+Shift+S` | Toggle tab sidebar |
| `Cmd+\` | Toggle AI sidebar |
| `Cmd+L` | Focus address bar |
| `Cmd+R` | Reload page |
| `Cmd+[` | Go back |
| `Cmd+]` | Go forward |

## Architecture

- **WheelBrowser/**: Main Swift package
  - **Sources/WheelBrowser/**: Source code
    - **Chat/**: AI assistant views and logic
    - **History/**: Browsing history and fuzzy search
    - **Settings/**: App settings and preferences

## License

MIT
