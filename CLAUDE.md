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

## OmniBar Animation Invariants (CRITICAL - READ BEFORE TOUCHING OMNIBAR)

The OmniBar has a recurring flashing/flickering bug caused by overlapping SwiftUI animation contexts. These rules MUST be followed to prevent regressions:

### Rule 1: No `.animation()` on the parent VStack
The `.animation()` modifier in `OmniBarCore.body` must ONLY be on `omniBarContent` and the find-bar `Group` — NEVER on the parent `VStack`. Placing it on the VStack causes panels to receive two overlapping animation contexts (implicit from `.animation()` + explicit from `withAnimation` in `setVisiblePanel()`), producing a flash.

### Rule 2: No `withAnimation` in mode-setting methods
`setMode()`, `nextMode()`, and `previousMode()` in `OmniBarState` must NOT wrap in `withAnimation`. Mode changes trigger `onChange(of: omniState.mode)` → `handleModeChange()` → `setVisiblePanel()` which has its own `withAnimation(panelSpring)`. Adding `withAnimation` in setMode creates nested animation contexts → flash.

### Rule 3: No dismiss-then-activate in `handleModeChange`
`handleModeChange()` must NOT call `dismissVisiblePanel()` before `activateMode()`. This creates two sequential `withAnimation` blocks — the first animates to `.none`, the second animates to the new panel — causing a visible flash. Instead, `activateMode()` directly sets the new panel (atomic swap).

### Rule 4: Guard delayed dismissals against stale focus
`handleFocusLost()` uses a 200ms delay. The delayed block MUST check `isInputFocused` before dismissing, because focus may have been regained during the delay. Without this check, the delayed dismiss fires after the new panel is already open → flash.

### Rule 5: No `.contentTransition(.opacity)` on streaming content
Views that update at high frequency (chat streaming, progress indicators) must NOT use `.contentTransition(.opacity)` or per-update `.animation()` modifiers. These create overlapping opacity fades that produce a flash effect.

### Rule 6: Avoid adding `@ObservedObject` to OmniBar
OmniBar already has 8+ observable objects. Each additional `@ObservedObject` increases the frequency of full body re-evaluations, which re-evaluate all panel visibility conditionals and can trigger spurious transitions. Extract sub-views that observe only what they need.

### Rule 7: No redundant `setVisiblePanel` calls
Handler methods (e.g., `handleFocusAISidebar`, `handleFocusSemanticSearch`) must NOT call `setVisiblePanel()` directly. `setMode()` triggers `onChange(of: mode)` → `handleModeChange()` → `activateMode()` → `setVisiblePanel()`. Calling it again creates redundant `withAnimation` transactions. `setVisiblePanel` has a guard (`guard visiblePanel != panel`) but calling it redundantly still creates unnecessary code paths.

### Rule 8: Non-animated state changes BEFORE animated panel changes
In `activateMode()`, load suggestions / search results / reading list BEFORE calling `setVisiblePanel()`. View model `@Published` mutations fire `objectWillChange` without an animation context. If they fire AFTER the animated panel change, they create non-animated body re-evals that can interleave with the transition animation.

### Rule 9: Set focus BEFORE mode in handler methods
Methods like `handleFocusAddressBar()` must set `isInputFocused = true` BEFORE `setMode()`. If mode is set first, `handleModeChange` fires and sees `isInputFocused == false`, causing it to dismiss the panel. Then the subsequent focus gain re-opens it → dismiss-then-show flash.

### Rule 10: No dead `@Published` properties on OmniBarState
Do not add `@Published` properties to `OmniBarState` that are not read by any view. Every `@Published` mutation fires `objectWillChange`, triggering a full body re-eval of OmniBar. (The removed `isFocused` property was doing this — never read, always triggering spurious updates.)

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
